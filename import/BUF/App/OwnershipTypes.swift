import Foundation

protocol OwnerStore: Sendable {
  static var appOwnerStore: AppOwnerStore { get }
}

struct ReminderStore: OwnerStore {
  static let appOwnerStore: AppOwnerStore = .reminder
}

struct SidecarStore: OwnerStore {
  static let appOwnerStore: AppOwnerStore = .sidecar
}

struct CalendarStore: OwnerStore {
  static let appOwnerStore: AppOwnerStore = .calendar
}

protocol CanonicalOwnerField: Sendable {
  associatedtype Owner: OwnerStore
  associatedtype Value

  static var canonicalPath: String { get }
}

extension CanonicalOwnerField {
  static var owner: AppOwnerStore { Owner.appOwnerStore }
  static var valueType: String { String(describing: Value.self) }
}

struct CanonicalOwnerFieldDescriptor: Sendable, Hashable {
  let canonicalPath: String
  let owner: AppOwnerStore
  let valueType: String
}

extension CanonicalOwnerFieldDescriptor {
  init<Field: CanonicalOwnerField>(_ field: Field.Type) {
    canonicalPath = Field.canonicalPath
    owner = Field.owner
    valueType = Field.valueType
  }
}

enum ProjectDocumentCanonicalOwnerMap {
  struct ProjectTitle: CanonicalOwnerField {
    typealias Owner = ReminderStore
    typealias Value = String
    static let canonicalPath = "project.title"
  }

  struct ProjectColor: CanonicalOwnerField {
    typealias Owner = ReminderStore
    typealias Value = String
    static let canonicalPath = "project.color"
  }

  struct TaskTitle: CanonicalOwnerField {
    typealias Owner = ReminderStore
    typealias Value = String
    static let canonicalPath = "task.title"
  }

  struct TaskReminderNote: CanonicalOwnerField {
    typealias Owner = ReminderStore
    typealias Value = String
    static let canonicalPath = "task.reminderNote"
  }

  struct TaskIsCompleted: CanonicalOwnerField {
    typealias Owner = ReminderStore
    typealias Value = Bool
    static let canonicalPath = "task.isCompleted"
  }

  struct TaskDueDate: CanonicalOwnerField {
    typealias Owner = ReminderStore
    typealias Value = Date?
    static let canonicalPath = "task.dueDate"
  }

  struct TaskHasExplicitTime: CanonicalOwnerField {
    typealias Owner = ReminderStore
    typealias Value = Bool
    static let canonicalPath = "task.hasExplicitTime"
  }

  struct TaskRecurrence: CanonicalOwnerField {
    typealias Owner = ReminderStore
    typealias Value = String?
    static let canonicalPath = "task.recurrence"
  }

  struct TaskPriority: CanonicalOwnerField {
    typealias Owner = ReminderStore
    typealias Value = Int
    static let canonicalPath = "task.priority"
  }

  struct TreeStructure: CanonicalOwnerField {
    typealias Owner = SidecarStore
    typealias Value = [String]
    static let canonicalPath = "treeStructure"
  }

  struct Ordering: CanonicalOwnerField {
    typealias Owner = SidecarStore
    typealias Value = [UUID]
    static let canonicalPath = "ordering"
  }

  struct ProjectNote: CanonicalOwnerField {
    typealias Owner = SidecarStore
    typealias Value = String
    static let canonicalPath = "project.note"
  }

  struct ProjectStage: CanonicalOwnerField {
    typealias Owner = SidecarStore
    typealias Value = ProjectProgressStage
    static let canonicalPath = "project.stage"
  }

  struct TaskScheduledDurationMinutes: CanonicalOwnerField {
    typealias Owner = SidecarStore
    typealias Value = Int?
    static let canonicalPath = "task.scheduledDurationMinutes"
  }

  struct TaskImportance: CanonicalOwnerField {
    typealias Owner = SidecarStore
    typealias Value = ImportanceLevel
    static let canonicalPath = "task.importance"
  }

  struct TaskBoardStage: CanonicalOwnerField {
    typealias Owner = SidecarStore
    typealias Value = BoardStage
    static let canonicalPath = "task.boardStage"
  }

  struct TaskIsFlagged: CanonicalOwnerField {
    typealias Owner = SidecarStore
    typealias Value = Bool
    static let canonicalPath = "task.isFlagged"
  }

  struct CalendarEventDate: CanonicalOwnerField {
    typealias Owner = CalendarStore
    typealias Value = Date
    static let canonicalPath = "eventDate"
  }

  struct CalendarDurationMinutes: CanonicalOwnerField {
    typealias Owner = CalendarStore
    typealias Value = Int
    static let canonicalPath = "duration"
  }

  static let fields: [CanonicalOwnerFieldDescriptor] = [
    .init(ProjectTitle.self),
    .init(ProjectColor.self),
    .init(TaskTitle.self),
    .init(TaskReminderNote.self),
    .init(TaskIsCompleted.self),
    .init(TaskDueDate.self),
    .init(TaskHasExplicitTime.self),
    .init(TaskRecurrence.self),
    .init(TaskPriority.self),
    .init(TreeStructure.self),
    .init(Ordering.self),
    .init(ProjectNote.self),
    .init(ProjectStage.self),
    .init(TaskScheduledDurationMinutes.self),
    .init(TaskImportance.self),
    .init(TaskBoardStage.self),
    .init(TaskIsFlagged.self),
    .init(CalendarEventDate.self),
    .init(CalendarDurationMinutes.self),
  ]

  static let ownerByCanonicalPath: [String: AppOwnerStore] = {
    var result: [String: AppOwnerStore] = [:]
    for field in fields {
      result[field.canonicalPath] = field.owner
    }
    return result
  }()
}

enum OwnershipBoundary {
  static func canAssign<Field: CanonicalOwnerField, Store: OwnerStore>(
    _ field: Field.Type,
    to _: Store.Type
  ) -> Bool where Field.Owner == Store {
    true
  }

  static func canAssign<Field: CanonicalOwnerField>(
    _ field: Field.Type,
    to owner: AppOwnerStore
  ) -> Bool {
    Field.owner == owner
  }
}
