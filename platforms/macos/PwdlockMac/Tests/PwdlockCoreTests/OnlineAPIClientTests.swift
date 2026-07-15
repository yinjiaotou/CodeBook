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
