import Foundation

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case timeline
    case schedule

    var id: String { rawValue }

    static let coreWorkspaceModes: [ViewMode] = [.timeline, .schedule]

    var title: String {
        switch self {
        case .timeline: "Timeline"
        case .schedule: "Schedule"
        }
    }

    var iconName: String {
        switch self {
        case .timeline: "chart.bar.xaxis"
        case .schedule: "calendar"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .timeline: "타임라인"
        case .schedule: "스케줄"
        }
    }
}

enum BoardStage: String, Codable, CaseIterable, Identifiable {
    case now
    case plan
    case area

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: "지금"
        case .plan: "계획"
        case .area: "Area"
        }
    }
}

enum ImportanceLevel: String, Codable, CaseIterable, Identifiable {
    case important
    case minor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .important: "중요"
        case .minor: "사소"
        }
    }
}

enum ProjectProgressStage: Int, Codable, CaseIterable, Identifiable {
    case decide = 0
    case `do` = 1
    case done = 2

    static let boardOrderRevisionStorageKey = "project.progressStage.boardOrderRevision"

    var id: Int { rawValue }
    var storageRawValue: String { String(rawValue) }
    var progressValue: Double {
        switch self {
        case .decide: 0.25
        case .do: 0.6
        case .done: 1
        }
    }

    var title: String {
        switch self {
        case .decide: "결정"
        case .do: "진행"
        case .done: "완료"
        }
    }

    var label: String { title }

    var iconName: String {
        switch self {
        case .decide: "questionmark.circle.fill"
        case .do: "circle.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    static func from(progress: Double) -> ProjectProgressStage {
        if progress >= 0.95 { return .done }
        if progress >= 0.45 { return .do }
        return .decide
    }
}

enum SyncReason: String, Codable {
    case bootstrap
    case eventStoreChanged
    case periodic
    case manual
}
