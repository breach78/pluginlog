import Foundation

enum ProjectTaskEditorSession: Equatable {
  case projectNote
  case taskTitle(UUID)
  case taskDate(UUID)
  case taskReminderNote(UUID)

  var taskID: UUID? {
    switch self {
    case .projectNote:
      return nil
    case .taskTitle(let taskID),
      .taskDate(let taskID),
      .taskReminderNote(let taskID):
      return taskID
    }
  }
}
