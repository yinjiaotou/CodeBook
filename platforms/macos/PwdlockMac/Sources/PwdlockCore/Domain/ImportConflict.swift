import Foundation

public struct ImportMergeSummary: Equatable, Sendable {
    public let added: Int
    public let identical: Int
    public let conflicts: Int

    public init(added: Int, identical: Int, conflicts: Int) {
        self.added = added
        self.identical = identical
        self.conflicts = conflicts
    }
}

public enum ConflictVariantKind: String, Codable, Sendable {
    case local
    case imported
}

public struct ConflictVariant: Equatable, Sendable {
    public let id: UUID
    public let kind: ConflictVariantKind
    public let sourceVaultID: UUID
    public let item: LoginItem

    public init(id: UUID, kind: ConflictVariantKind, sourceVaultID: UUID, item: LoginItem) {
        self.id = id
        self.kind = kind
        self.sourceVaultID = sourceVaultID
        self.item = item
    }
}

public struct ImportConflict: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let recordID: UUID
    public let title: String
    public let createdAt: Date
    public let local: ConflictVariant
    public let imported: ConflictVariant

    public init(
        id: UUID,
        recordID: UUID,
        title: String,
        createdAt: Date,
        local: ConflictVariant,
        imported: ConflictVariant
    ) {
        self.id = id
        self.recordID = recordID
        self.title = title
        self.createdAt = createdAt
        self.local = local
        self.imported = imported
    }
}

public struct ManualLoginMerge: Equatable, Sendable {
    public var title: String
    public var username: String
    public var password: String
    public var url: String
    public var category: String
    public var note: String

    public init(
        title: String,
        username: String,
        password: String,
        url: String,
        category: String,
        note: String
    ) {
        self.title = title
        self.username = username
        self.password = password
        self.url = url
        self.category = category
        self.note = note
    }
}
