import Foundation

enum ProjectNoteReminderPolicy {
  static let title = "프로젝트 노트"
  static let lowPriority = 9

  static func isProjectNoteReminder(title: String, priority: Int) -> Bool {
    title.trimmingCharacters(in: .whitespacesAndNewlines) == Self.title
      && priority == Self.lowPriority
  }

  static func projectNoteText(in tasks: [RetainedTask]) -> String? {
    tasks.first(where: isProjectNoteReminder(_:))?.noteText
  }

  static func visibleTasks(_ tasks: [RetainedTask]) -> [RetainedTask] {
    tasks.filter { !isProjectNoteReminder($0) }
  }

  private static func isProjectNoteReminder(_ task: RetainedTask) -> Bool {
    isProjectNoteReminder(title: task.title, priority: task.priority)
  }
}
