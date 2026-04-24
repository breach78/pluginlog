import Foundation

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case compass
    case journal
    case timeline
    case schedule

    var id: String { rawValue }

    static let coreWorkspaceModes: [ViewMode] = [.timeline, .schedule]
    static let privateObsidianModes: [ViewMode] = [.journal, .compass]

    var title: String {
        switch self {
        case .compass: "Compass"
        case .journal: "Journal"
        case .timeline: "Timeline"
        case .schedule: "Schedule"
        }
    }

    var iconName: String {
        switch self {
        case .compass: "location.north.line.fill"
        case .journal: "book.closed"
        case .timeline: "chart.bar.xaxis"
        case .schedule: "calendar"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .compass: "나침반"
        case .journal: "저널"
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

enum AttachmentOwnerType: String, Codable {
    case project
    case task
}

enum SyncReason: String, Codable {
    case bootstrap
    case eventStoreChanged
    case periodic
    case manual
}
