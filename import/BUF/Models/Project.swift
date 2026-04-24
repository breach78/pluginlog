import Foundation
import SwiftData

enum ProjectProgressStage: Int, CaseIterable, Sendable {
    case `do` = 0
    case decide = 1
    case delegate = 2
    case delete = 3
    case area = 4

    static let boardOrderRevisionStorageKey = "project.board.order.revision"
    var progressValue: Double {
        Double(rawValue) * 0.25
    }

    var label: String {
        switch self {
        case .do:
            return "DO"
        case .decide:
            return "DECIDE"
        case .delegate:
            return "DELEGATE"
        case .delete:
            return "DELETE"
        case .area:
            return "Area"
        }
    }

    var storageRawValue: String {
        String(rawValue)
    }

    var iconName: String {
        switch self {
        case .do:
            return "bolt.fill"
        case .decide:
            return "clock.fill"
        case .delegate:
            return "arrowshape.turn.up.right.fill"
        case .delete:
            return "trash.fill"
        case .area:
            return "square.grid.2x2"
        }
    }

    static func from(progress rawProgress: Double) -> ProjectProgressStage {
        let clamped = min(max(0, rawProgress), 1)
        let snappedIndex = Int((clamped * 4).rounded())
        return ProjectProgressStage(rawValue: min(max(0, snappedIndex), 4)) ?? .do
    }

    static func snappedProgress(from rawProgress: Double) -> Double {
        from(progress: rawProgress).progressValue
    }

    static func touchBoardOrderRevision() {
        let defaults = UserDefaults.standard
        let nextRevision = defaults.integer(forKey: boardOrderRevisionStorageKey) + 1
        defaults.set(nextRevision, forKey: boardOrderRevisionStorageKey)
    }
}

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var calendarIdentifier: String
    var calendarExternalIdentifier: String
    var title: String
    var colorHex: String?

    var startDate: Date?
    var deadline: Date?
    var projectNoteMarkdown: String

    var isArchived: Bool
    var archivedAt: Date?
    var isDirty: Bool

    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    var tasks: [TaskItem]

    init(
        id: UUID = UUID(),
        calendarIdentifier: String,
        calendarExternalIdentifier: String,
        title: String,
        colorHex: String? = nil,
        startDate: Date? = nil,
        deadline: Date? = nil,
        projectNoteMarkdown: String = "",
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        isDirty: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.calendarIdentifier = calendarIdentifier
        self.calendarExternalIdentifier = calendarExternalIdentifier
        self.title = title
        self.colorHex = colorHex
        self.startDate = startDate
        self.deadline = deadline
        self.projectNoteMarkdown = projectNoteMarkdown
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.isDirty = isDirty
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.tasks = []
    }
}

extension Project {
    var progress: Double {
        guard !tasks.isEmpty else { return 0 }

        let done = tasks.filter(\.isCompleted).count
        return Double(done) / Double(tasks.count)
    }
}
