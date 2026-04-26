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
    case `do` = 0
    case decide = 1
    case area = 2
    case later = 3

    static let boardOrderRevisionStorageKey = "project.progressStage.boardOrderRevision"

    var id: Int { rawValue }
    var storageRawValue: String { String(rawValue) }
    var progressValue: Double {
        Double(rawValue) / Double(max(1, Self.allCases.count - 1))
    }

    var title: String {
        switch self {
        case .do: "Do"
        case .decide: "Decide"
        case .area: "Area"
        case .later: "Later"
        }
    }

    var label: String { title }

    var iconName: String {
        switch self {
        case .do: "bolt.fill"
        case .decide: "clock.fill"
        case .area: "square.grid.2x2"
        case .later: "archivebox.fill"
        }
    }

    static func from(progress: Double) -> ProjectProgressStage {
        let clamped = min(max(progress, 0), 1)
        let snappedIndex = Int((clamped * Double(Self.allCases.count - 1)).rounded())
        return ProjectProgressStage(rawValue: snappedIndex) ?? .do
    }

    static func fromStorageValue(_ value: String?) -> ProjectProgressStage? {
        guard let normalized = normalizedStageValue(value) else { return nil }
        if let intValue = Int(normalized), let stage = ProjectProgressStage(rawValue: intValue) {
            return stage
        }
        return Self.allCases.first { stage in
            normalizedStageValue(stage.title) == normalized
                || normalizedStageValue(stage.label) == normalized
        }
    }

    private static func normalizedStageValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }
}

enum SyncReason: String, Codable {
    case bootstrap
    case eventStoreChanged
    case periodic
    case manual
}
