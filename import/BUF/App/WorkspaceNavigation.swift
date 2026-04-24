import Foundation

// Phase 6 cutover:
// UI read paths now use canonical project IDs only.
// Workspace node identity stays inside sidebar/query internals and no longer leaks through navigation.

enum WorkspaceProjectReference: Hashable, Identifiable {
    case project(UUID)

    var id: UUID {
        switch self {
        case .project(let id):
            return id
        }
    }

    var projectID: UUID? {
        switch self {
        case .project(let id):
            return id
        }
    }
}

enum WorkspaceNavigationTarget: Equatable {
    case projectTop(projectID: UUID)
    case projectNotes(projectID: UUID)
    case projectAttachments(projectID: UUID)
    case taskRow(projectID: UUID, taskID: UUID)
    case taskDetail(projectID: UUID, taskID: UUID)

    var projectID: UUID {
        switch self {
        case .projectTop(let projectID),
             .projectNotes(let projectID),
             .projectAttachments(let projectID):
            return projectID
        case .taskRow(let projectID, _),
             .taskDetail(let projectID, _):
            return projectID
        }
    }

    var taskID: UUID? {
        switch self {
        case .taskRow(_, let taskID), .taskDetail(_, let taskID):
            return taskID
        case .projectTop, .projectNotes, .projectAttachments:
            return nil
        }
    }

    var scrollAnchorID: String {
        switch self {
        case .projectTop(let projectID):
            return "workspace.project.top.\(projectID.uuidString)"
        case .projectNotes(let projectID):
            return "workspace.project.notes.\(projectID.uuidString)"
        case .projectAttachments(let projectID):
            return "workspace.project.attachments.\(projectID.uuidString)"
        case .taskRow(_, let taskID):
            return "workspace.task.row.\(taskID.uuidString)"
        case .taskDetail(_, let taskID):
            return "workspace.task.detail.\(taskID.uuidString)"
        }
    }

    var requiresDeferredScroll: Bool {
        switch self {
        case .taskDetail:
            return true
        case .projectTop, .projectNotes, .projectAttachments, .taskRow:
            return false
        }
    }
}

struct WorkspaceNavigationRequest: Identifiable, Equatable {
    let id: UUID
    let target: WorkspaceNavigationTarget

    init(id: UUID = UUID(), target: WorkspaceNavigationTarget) {
        self.id = id
        self.target = target
    }
}
