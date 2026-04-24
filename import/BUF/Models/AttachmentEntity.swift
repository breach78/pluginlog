import Foundation
import SwiftData

@Model
final class AttachmentEntity {
    @Attribute(.unique) var id: UUID

    var ownerTypeRaw: String
    var ownerID: UUID

    var relativePath: String
    var originalFilename: String
    var mimeType: String
    var byteSize: Int64
    var sha256: String

    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerType: AttachmentOwnerType,
        ownerID: UUID,
        relativePath: String,
        originalFilename: String,
        mimeType: String,
        byteSize: Int64,
        sha256: String,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.ownerTypeRaw = ownerType.rawValue
        self.ownerID = ownerID
        self.relativePath = relativePath
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.sha256 = sha256
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension AttachmentEntity {
    var ownerType: AttachmentOwnerType {
        get { AttachmentOwnerType(rawValue: ownerTypeRaw) ?? .task }
        set { ownerTypeRaw = newValue.rawValue }
    }
}
