import Foundation

enum WorkspaceSearchEntityKind: Int, Codable, Equatable, Sendable {
    case project = 0
    case task = 1
}

enum WorkspaceSearchResultDisposition: Int, Codable, Equatable, Sendable {
    case regular = 0
    case completedTask = 1
    case archivedProject = 2

    var sectionRank: Int {
        switch self {
        case .regular:
            return 0
        case .completedTask, .archivedProject:
            return 1
        }
    }

    var isDimmed: Bool {
        self != .regular
    }

    var sectionHeaderTitle: String? {
        isDimmed ? "완료 / 아카이브" : nil
    }

    var statusLabel: String? {
        switch self {
        case .regular:
            return nil
        case .completedTask:
            return "완료"
        case .archivedProject:
            return "아카이브"
        }
    }
}

enum WorkspaceSearchMatchKind: Int, Codable, Equatable, Sendable {
    case projectTitle = 0
    case taskTitle = 1
    case projectNote = 2
    case taskReminderNote = 3
    case taskNote = 4
    case projectAttachment = 5
    case taskAttachment = 6

    var sortRank: Int {
        rawValue
    }

    var label: String {
        switch self {
        case .projectTitle:
            return "프로젝트"
        case .taskTitle:
            return "할일 제목"
        case .projectNote:
            return "프로젝트 노트"
        case .taskReminderNote:
            return "리마인더 노트"
        case .taskNote:
            return "할일 노트"
        case .projectAttachment:
            return "프로젝트 첨부"
        case .taskAttachment:
            return "할일 첨부"
        }
    }
}

struct WorkspaceSearchResult: Identifiable, Equatable {
    let id: String
    let entityKind: WorkspaceSearchEntityKind
    let disposition: WorkspaceSearchResultDisposition
    let projectID: UUID
    let taskID: UUID?
    let matchKind: WorkspaceSearchMatchKind
    let title: String
    let subtitle: String
    let preview: String
    let navigationTarget: WorkspaceNavigationTarget

    fileprivate let sortRank: Int
}

enum WorkspaceSearchService {
    static func normalizedTokens(from raw: String) -> [String] {
        raw
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent)
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func search(
        canonicalIndex: [WorkspaceSearchIndexEntry],
        rawQuery: String,
        limit: Int = 48
    ) -> [WorkspaceSearchResult] {
        let tokens = normalizedTokens(from: rawQuery)
        guard !tokens.isEmpty else { return [] }

        var results: [WorkspaceSearchResult] = []
        results.reserveCapacity(min(limit, max(canonicalIndex.count, 8)))

        for entry in canonicalIndex where !entry.isExcludedFromSearch {
            guard matchesAllTokens(entry.corpus, tokens: tokens) else { continue }
            let candidates = entry.candidates.map {
                MatchCandidate(
                    kind: $0.kind,
                    fieldText: $0.fieldText,
                    preview: $0.preview,
                    matchedTokenCount: matchedTokenCount(in: $0.fieldText, tokens: tokens)
                )
            }
            guard let match = bestCandidate(from: candidates) else { continue }
            results.append(searchResult(for: entry, match: match))
        }

        return sorted(results: results, limit: limit)
    }

    static func sorted(results: [WorkspaceSearchResult], limit: Int = 48) -> [WorkspaceSearchResult] {
        results
            .sorted(by: compareResults)
            .prefix(limit)
            .map { $0 }
    }

    private struct MatchCandidate {
        let kind: WorkspaceSearchMatchKind
        let fieldText: String
        let preview: String
        let matchedTokenCount: Int
    }

    private static func searchResult(
        for entry: WorkspaceSearchIndexEntry,
        match: MatchCandidate
    ) -> WorkspaceSearchResult {
        let preview = snippet(from: match.preview)
        let navigationTarget: WorkspaceNavigationTarget
        switch entry.entityKind {
        case .project:
            navigationTarget = .projectTop(projectID: entry.projectID)
        case .task:
            switch match.kind {
            case .taskTitle:
                navigationTarget = .taskRow(projectID: entry.projectID, taskID: entry.taskID!)
            case .taskReminderNote, .taskNote, .taskAttachment:
                navigationTarget = .taskDetail(projectID: entry.projectID, taskID: entry.taskID!)
            case .projectTitle, .projectNote, .projectAttachment:
                navigationTarget = .taskDetail(projectID: entry.projectID, taskID: entry.taskID!)
            }
        }

        let subtitle: String
        switch entry.entityKind {
        case .project:
            subtitle = match.kind == .projectTitle
                ? "\(entry.subtitlePrefix) · \(match.kind.label)"
                : "\(entry.subtitlePrefix) · \(match.kind.label) · \(preview)"
        case .task:
            subtitle = "\(entry.subtitlePrefix) · \(match.kind.label)"
        }

        return WorkspaceSearchResult(
            id: entry.id,
            entityKind: entry.entityKind,
            disposition: entry.disposition,
            projectID: entry.projectID,
            taskID: entry.taskID,
            matchKind: match.kind,
            title: entry.title,
            subtitle: subtitle,
            preview: preview,
            navigationTarget: navigationTarget,
            sortRank: match.kind.sortRank
        )
    }

    private static func candidate(
        kind: WorkspaceSearchMatchKind,
        fieldText: String,
        preview: String,
        tokens: [String]
    ) -> MatchCandidate {
        MatchCandidate(
            kind: kind,
            fieldText: fieldText,
            preview: preview,
            matchedTokenCount: matchedTokenCount(in: fieldText, tokens: tokens)
        )
    }

    private static func bestCandidate(from candidates: [MatchCandidate]) -> MatchCandidate? {
        candidates
            .filter { !$0.fieldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.matchedTokenCount > 0 }
            .sorted { lhs, rhs in
                if lhs.matchedTokenCount != rhs.matchedTokenCount {
                    return lhs.matchedTokenCount > rhs.matchedTokenCount
                }
                if lhs.kind.sortRank != rhs.kind.sortRank {
                    return lhs.kind.sortRank < rhs.kind.sortRank
                }
                return lhs.preview.count < rhs.preview.count
            }
            .first
    }

    private static func compareResults(_ lhs: WorkspaceSearchResult, _ rhs: WorkspaceSearchResult) -> Bool {
        if lhs.disposition.sectionRank != rhs.disposition.sectionRank {
            return lhs.disposition.sectionRank < rhs.disposition.sectionRank
        }
        if lhs.disposition != rhs.disposition {
            return lhs.disposition.rawValue < rhs.disposition.rawValue
        }
        if lhs.sortRank != rhs.sortRank {
            return lhs.sortRank < rhs.sortRank
        }
        if lhs.entityKind != rhs.entityKind {
            switch (lhs.entityKind, rhs.entityKind) {
            case (.project, .task):
                return true
            case (.task, .project):
                return false
            case (.project, .project), (.task, .task):
                break
            }
        }
        if lhs.title.localizedCaseInsensitiveCompare(rhs.title) != .orderedSame {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private static func matchesAllTokens(_ source: String, tokens: [String]) -> Bool {
        let normalized = normalizedSource(source)
        guard !normalized.isEmpty else { return false }
        return tokens.allSatisfy { normalized.contains($0) }
    }

    private static func matchedTokenCount(in source: String, tokens: [String]) -> Int {
        let normalized = normalizedSource(source)
        guard !normalized.isEmpty else { return 0 }
        return tokens.reduce(into: 0) { count, token in
            if normalized.contains(token) {
                count += 1
            }
        }
    }

    private static func normalizedSource(_ source: String) -> String {
        source.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent)
    }

    private static func snippet(from text: String, limit: Int = 72) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > limit else { return compact }
        let index = compact.index(compact.startIndex, offsetBy: limit)
        return String(compact[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
