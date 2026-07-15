import Foundation

public enum OnlineAPIError: Error, Equatable {
    case invalidResponse
    case rejected
    case transportFailed
}

public struct OnlineSession: Sendable, Equatable {
    public let accessToken: String
    public init(accessToken: String) { self.accessToken = accessToken }
}

public struct OnlineDevice: Sendable, Equatable, Decodable { public let id: UUID }
public struct OnlineVault: Sendable, Equatable, Decodable { public let id: UUID; public let encryptedKeyEnvelope: String }

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

    public func createVault(encryptedKeyEnvelope: String, accessToken: String) async throws -> OnlineVault {
        try await authorized(path: "vaults", body: VaultRequest(encryptedKeyEnvelope: encryptedKeyEnvelope), token: accessToken)
    }

    public func listVaults(accessToken: String) async throws -> [OnlineVault] {
        var request = URLRequest(url: baseURL.appending(path: "vaults"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await transport(request)
            guard let response = response as? HTTPURLResponse else { throw OnlineAPIError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw OnlineAPIError.rejected }
            return try JSONDecoder().decode([OnlineVault].self, from: data)
        } catch let error as OnlineAPIError { throw error }
        catch { throw OnlineAPIError.transportFailed }
    }

    private func authenticate(path: String, loginName: String, password: String) async throws -> OnlineSession {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Credentials(loginName: loginName, password: password))
        do {
            let (data, response) = try await transport(request)
            guard let response = response as? HTTPURLResponse else { throw OnlineAPIError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw OnlineAPIError.rejected }
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
            guard (200..<300).contains(response.statusCode) else { throw OnlineAPIError.rejected }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as OnlineAPIError { throw error }
        catch { throw OnlineAPIError.transportFailed }
    }

    private struct Credentials: Codable { let loginName: String; let password: String }
    private struct TokenResponse: Codable { let accessToken: String }
    private struct DeviceRequest: Codable { let label: String; let publicSigningKey: String }
    private struct VaultRequest: Codable { let encryptedKeyEnvelope: String }
}
