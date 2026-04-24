import Foundation
import SwiftData

enum ProjectHistoryEventKind: String, CaseIterable {
    case projectCreated
    case projectUpdated
    case projectTimelineChanged
    case projectArchived
    case projectRestored
    case projectDeleted
    case taskCreated
    case taskCompleted
    case taskReopened
    case taskUpdated
    case taskScheduleChanged
    case taskMoved
    case taskDeleted
    case projectNoteSaved
    case taskReminderNoteSaved
    case attachmentAdded
}

enum ProjectHistoryEventSource: String {
    case local
    case backfill
}

@Model
final class ProjectHistoryEvent {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var eventKey: String

    var projectID: UUID
    var occurredAt: Date
    var kindRaw: String
    var sourceRaw: String

    var taskID: UUID?
    var taskTitleSnapshot: String?
    var noteTextSnapshot: String?
    var attachmentFilename: String?
    var detailTextSnapshot: String?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        eventKey: String,
        projectID: UUID,
        occurredAt: Date,
        kind: ProjectHistoryEventKind,
        source: ProjectHistoryEventSource = .local,
        taskID: UUID? = nil,
        taskTitleSnapshot: String? = nil,
        noteTextSnapshot: String? = nil,
        attachmentFilename: String? = nil,
        detailTextSnapshot: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.eventKey = eventKey
        self.projectID = projectID
        self.occurredAt = occurredAt
        self.kindRaw = kind.rawValue
        self.sourceRaw = source.rawValue
        self.taskID = taskID
        self.taskTitleSnapshot = taskTitleSnapshot
        self.noteTextSnapshot = noteTextSnapshot
        self.attachmentFilename = attachmentFilename
        self.detailTextSnapshot = detailTextSnapshot
        self.createdAt = createdAt
    }
}

extension ProjectHistoryEvent {
    var kind: ProjectHistoryEventKind {
        get { ProjectHistoryEventKind(rawValue: kindRaw) ?? .taskCreated }
        set { kindRaw = newValue.rawValue }
    }

    var source: ProjectHistoryEventSource {
        get { ProjectHistoryEventSource(rawValue: sourceRaw) ?? .local }
        set { sourceRaw = newValue.rawValue }
    }
}
