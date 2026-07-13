import Foundation

public struct LoginItem: Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let username: String
    public let password: String
    public let url: String
    public let category: String
    public let note: String
    public let createdAt: Date
    public let updatedAt: Date
    public let revision: Int
    public let deviceID: UUID

    public init(
        id: UUID,
        title: String,
        username: String,
        password: String,
        url: String,
        category: String,
        note: String,
        createdAt: Date,
        updatedAt: Date,
        revision: Int,
        deviceID: UUID
    ) {
        self.id = id
        self.title = title
        self.username = username
        self.password = password
        self.url = url
        self.category = category
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
    }
}
