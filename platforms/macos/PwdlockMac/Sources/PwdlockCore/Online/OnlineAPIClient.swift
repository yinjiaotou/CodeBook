import Foundation

public enum OnlineAPIError: Error, Equatable {
    case invalidResponse
    case unauthorized
    case rejected
    case transportFailed
}

public struct OnlineSession: Sendable, Equatable {
    public let accessToken: String
    public init(accessToken: String) { self.accessToken = accessToken }
}

public struct OnlineDevice: Sendable, Equatable, Decodable {
    public let id: UUID
    /// Device creation responses only need to return the identifier. Device list
    /// responses include this key and are the only responses used for verification.
    public let publicSigningKey: String

    public init(id: UUID, publicSigningKey: String = "") {
        self.id = id
        self.publicSigningKey = publicSigningKey
    }

    private enum CodingKeys: String, CodingKey { case id, publicSigningKey }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        publicSigningKey = try container.decodeIfPresent(String.self, forKey: .publicSigningKey) ?? ""
    }
}
public struct OnlineVault: Sendable, Equatable, Decodable { public let id: UUID; public let encryptedKeyEnvelope: String }
public struct OnlineRemoteChange: Sendable, Equatable, Decodable { public let sequence: String; public let changeId: String; public let deviceId: UUID; public let ciphertext: String; public let signature: String }

public protocol OnlineAuthenticating: Sendable {
    func register(loginName: String, password: String) async throws -> OnlineSession
    func login(loginName: String, password: String) async throws -> OnlineSession
}

public struct OnlineAPIClient: OnlineAuthenticating, Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let baseURL: URL
    private let transport: Transport

    public init(baseURL: URL, transport: @escaping Transport = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func register(loginName: String, password: String) async throws -> OnlineSession {
        try await authenticate(path: "auth/register", loginName: loginName, password: password)
    }

    public func login(loginName: String, password: String) async throws -> OnlineSession {
        try await authenticate(path: "auth/login", loginName: loginName, password: password)
    }

    public func registerDevice(label: String, publicSigningKey: String, accessToken: String) async throws -> OnlineDevice {
        try await authorized(path: "devices", body: DeviceRequest(label: label, publicSigningKey: publicSigningKey), token: accessToken)
    }

    public func listDevices(accessToken: String) async throws -> [OnlineDevice] {
        var request = URLRequest(url: baseURL.appending(path: "devices"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw OnlineAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw responseError(http) }
        return try JSONDecoder().decode([OnlineDevice].self, from: data)
    }

    public func createVault(encryptedKeyEnvelope: String, accessToken: String) async throws -> OnlineVault {
        try await authorized(path: "vaults", body: VaultRequest(encryptedKeyEnvelope: encryptedKeyEnvelope), token: accessToken)
    }

    public func listVaults(accessToken: String) async throws -> [OnlineVault] {
        var request = URLRequest(url: baseURL.appending(path: "vaults"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await transport(request)
            guard let response = response as? HTTPURLResponse else { throw OnlineAPIError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw responseError(response) }
            return try JSONDecoder().decode([OnlineVault].self, from: data)
        } catch let error as OnlineAPIError { throw error }
        catch { throw OnlineAPIError.transportFailed }
    }

    public func appendChange(vaultID: UUID, changeID: UUID, deviceID: UUID, envelope: OnlineSyncEnvelope, accessToken: String) async throws -> OnlineRemoteChange {
        try await authorized(
            path: "vaults/\(vaultID.uuidString.lowercased())/changes",
            body: ChangeRequest(
                changeId: changeID.uuidString.lowercased(),
                deviceId: deviceID.uuidString.lowercased(),
                ciphertext: envelope.ciphertext,
                signature: envelope.signature
            ),
            token: accessToken
        )
    }

    public func listChanges(vaultID: UUID, after: String? = nil, accessToken: String) async throws -> [OnlineRemoteChange] {
        var components = URLComponents(url: baseURL.appending(path: "vaults/\(vaultID.uuidString)/changes"), resolvingAgainstBaseURL: false)!
        if let after { components.queryItems = [URLQueryItem(name: "after", value: after)] }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw OnlineAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw responseError(http) }
        return try JSONDecoder().decode([OnlineRemoteChange].self, from: data)
    }

    private func authenticate(path: String, loginName: String, password: String) async throws -> OnlineSession {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Credentials(loginName: loginName, password: password))
        do {
            let (data, response) = try await transport(request)
            guard let response = response as? HTTPURLResponse else { throw OnlineAPIError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw responseError(response) }
            return OnlineSession(accessToken: try JSONDecoder().decode(TokenResponse.self, from: data).accessToken)
        } catch let error as OnlineAPIError {
            throw error
        } catch {
            throw OnlineAPIError.transportFailed
        }
    }

    private func authorized<Response: Decodable, Body: Encodable>(path: String, body: Body, token: String) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        do {
            let (data, response) = try await transport(request)
            guard let response = response as? HTTPURLResponse else { throw OnlineAPIError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw responseError(response) }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as OnlineAPIError { throw error }
        catch { throw OnlineAPIError.transportFailed }
    }

    private struct Credentials: Codable { let loginName: String; let password: String }
    private struct TokenResponse: Codable { let accessToken: String }
    private struct DeviceRequest: Codable { let label: String; let publicSigningKey: String }
    private struct VaultRequest: Codable { let encryptedKeyEnvelope: String }
    private struct ChangeRequest: Codable { let changeId: String; let deviceId: String; let ciphertext: String; let signature: String }

    private func responseError(_ response: HTTPURLResponse) -> OnlineAPIError {
        response.statusCode == 401 ? .unauthorized : .rejected
    }
}
