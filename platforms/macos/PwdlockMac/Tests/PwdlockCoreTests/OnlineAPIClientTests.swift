import Foundation
import Testing
@testable import PwdlockCore

@Test("online API sends credentials only to auth endpoint and reads an access token")
func onlineAPILoginContract() async throws {
    let baseURL = try #require(URL(string: "https://sync.example.test/v1"))
    let client = OnlineAPIClient(baseURL: baseURL) { request in
        #expect(request.url?.absoluteString == "https://sync.example.test/v1/auth/login")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        #expect(String(decoding: body, as: UTF8.self).contains("alice@example.test"))
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data("{\"accessToken\":\"token\"}".utf8), response)
    }
    let session = try await client.login(loginName: "alice@example.test", password: "not-a-vault-password")
    #expect(session.accessToken == "token")
}

@Test("online API lists only vault envelopes authorized for the current account")
func onlineAPIListVaultsContract() async throws {
    let baseURL = try #require(URL(string: "https://sync.example.test/v1"))
    let client = OnlineAPIClient(baseURL: baseURL) { request in
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data("[{\"id\":\"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa\",\"encryptedKeyEnvelope\":\"YWJjZA==\"}]".utf8), response)
    }
    let vaults = try await client.listVaults(accessToken: "token")
    #expect(vaults.count == 1)
}

@Test("online API authenticates device and vault setup requests")
func onlineAPISetupContract() async throws {
    let baseURL = try #require(URL(string: "https://sync.example.test/v1"))
    let client = OnlineAPIClient(baseURL: baseURL) { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
        if request.url!.path.hasSuffix("devices") { return (Data("{\"id\":\"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa\"}".utf8), response) }
        return (Data("{\"id\":\"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb\",\"encryptedKeyEnvelope\":\"YWJjZA==\"}".utf8), response)
    }
    let device = try await client.registerDevice(label: "Mac", publicSigningKey: Data(repeating: 1, count: 32).base64EncodedString(), accessToken: "token")
    let vault = try await client.createVault(encryptedKeyEnvelope: Data(repeating: 2, count: 32).base64EncodedString(), accessToken: "token")
    #expect(device.id.uuidString.lowercased() == "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    #expect(vault.id.uuidString.lowercased() == "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
}
