import Foundation
import SwiftData

@Model
final class TaskProjectClonePlacement {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var projectID: UUID
    var parentTaskID: UUID?
    var rowOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        taskID: UUID,
        projectID: UUID,
        parentTaskID: UUID? = nil,
        rowOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.taskID = taskID
        self.projectID = projectID
        self.parentTaskID = parentTaskID
        self.rowOrder = rowOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
