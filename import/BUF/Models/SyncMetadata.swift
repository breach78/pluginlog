import Foundation
import SwiftData

@Model
final class SyncState {
    @Attribute(.unique) var id: String
    var lastFullSyncAt: Date?
    var lastPeriodicSyncAt: Date?
    var lastError: String?
    var lastConflictAt: Date?

    init(
        id: String = "default",
        lastFullSyncAt: Date? = nil,
        lastPeriodicSyncAt: Date? = nil,
        lastError: String? = nil,
        lastConflictAt: Date? = nil
    ) {
        self.id = id
        self.lastFullSyncAt = lastFullSyncAt
        self.lastPeriodicSyncAt = lastPeriodicSyncAt
        self.lastError = lastError
        self.lastConflictAt = lastConflictAt
    }
}

@Model
final class ConflictLog {
    @Attribute(.unique) var id: UUID
    var entityType: String
    var entityID: UUID
    var field: String
    var localValue: String
    var remoteValue: String
    var resolvedBy: String
    var resolvedAt: Date

    init(
        id: UUID = UUID(),
        entityType: String,
        entityID: UUID,
        field: String,
        localValue: String,
        remoteValue: String,
        resolvedBy: String,
        resolvedAt: Date = .now
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.field = field
        self.localValue = localValue
        self.remoteValue = remoteValue
        self.resolvedBy = resolvedBy
        self.resolvedAt = resolvedAt
    }
}
