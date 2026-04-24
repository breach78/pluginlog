import Foundation
import SwiftData

/// Phase 13 cleanup boundary freeze:
/// Live history recording stays in app steady-state.
/// Legacy backfill diagnostics were quarantined to test support in Phase 1.
enum ProjectHistoryService {
    static func recordProjectCreated(
        projectID: UUID,
        projectTitle: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .projectCreated),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .projectCreated,
                source: source,
                taskTitleSnapshot: projectTitle
            ),
            in: context
        )
    }

    static func recordTaskCreated(
        projectID: UUID,
        taskID: UUID,
        taskTitle: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .taskCreated),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .taskCreated,
                source: source,
                taskID: taskID,
                taskTitleSnapshot: taskTitle
            ),
            in: context
        )
    }

    static func recordTaskCompletionChange(
        projectID: UUID,
        taskID: UUID,
        taskTitle: String,
        isCompleted: Bool,
        completionDate: Date?,
        localUpdatedAt: Date,
        source: ProjectHistoryEventSource = .local,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        let kind: ProjectHistoryEventKind = isCompleted ? .taskCompleted : .taskReopened
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: kind),
                projectID: projectID,
                occurredAt: completionDate ?? localUpdatedAt,
                kind: kind,
                source: source,
                taskID: taskID,
                taskTitleSnapshot: taskTitle
            ),
            in: context
        )
    }

    static func recordProjectArchived(
        projectID: UUID,
        projectTitle: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .projectArchived),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .projectArchived,
                source: source,
                taskTitleSnapshot: projectTitle,
                detailTextSnapshot: "프로젝트를 아카이브했다."
            ),
            in: context
        )
    }

    static func recordProjectNoteSaved(
        projectID: UUID,
        note: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .projectNoteSaved),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .projectNoteSaved,
                source: source,
                noteTextSnapshot: note
            ),
            in: context
        )
    }

    static func recordTaskReminderNoteSaved(
        projectID: UUID,
        taskID: UUID,
        taskTitle: String,
        note: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .taskReminderNoteSaved),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .taskReminderNoteSaved,
                source: source,
                taskID: taskID,
                taskTitleSnapshot: taskTitle,
                noteTextSnapshot: note
            ),
            in: context
        )
    }

    static func recordAttachmentAdded(
        projectID: UUID,
        taskID: UUID? = nil,
        taskTitleSnapshot: String? = nil,
        filename: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .attachmentAdded),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .attachmentAdded,
                source: source,
                taskID: taskID,
                taskTitleSnapshot: taskTitleSnapshot,
                attachmentFilename: filename
            ),
            in: context
        )
    }

    static func recordProjectUpdated(
        projectID: UUID,
        projectTitle: String,
        summary: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else { return }
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .projectUpdated),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .projectUpdated,
                source: source,
                taskTitleSnapshot: projectTitle,
                detailTextSnapshot: trimmedSummary
            ),
            in: context
        )
    }

    static func recordProjectTimelineChanged(
        projectID: UUID,
        projectTitle: String,
        previousStartDate: Date?,
        previousDeadline: Date?,
        nextStartDate: Date?,
        nextDeadline: Date?,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        guard
            let summary = projectTimelineChangeSummary(
                previousStartDate: previousStartDate,
                previousDeadline: previousDeadline,
                nextStartDate: nextStartDate,
                nextDeadline: nextDeadline
            )
        else { return }
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .projectTimelineChanged),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .projectTimelineChanged,
                source: source,
                taskTitleSnapshot: projectTitle,
                detailTextSnapshot: summary
            ),
            in: context
        )
    }

    static func recordTaskScheduleChanged(
        projectID: UUID,
        taskID: UUID,
        taskTitle: String,
        summary: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else { return }
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .taskScheduleChanged),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .taskScheduleChanged,
                source: source,
                taskID: taskID,
                taskTitleSnapshot: taskTitle,
                detailTextSnapshot: trimmedSummary
            ),
            in: context
        )
    }

    static func recordProjectRestored(
        projectID: UUID,
        projectTitle: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .projectRestored),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .projectRestored,
                source: source,
                taskTitleSnapshot: projectTitle,
                detailTextSnapshot: "프로젝트를 복원했다."
            ),
            in: context
        )
    }

    static func recordProjectDeleted(
        projectID: UUID,
        projectTitle: String,
        taskCount: Int,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        let summary =
            taskCount > 0
            ? "프로젝트와 할일 \(taskCount)개를 영구 삭제했다."
            : "프로젝트를 영구 삭제했다."
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .projectDeleted),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .projectDeleted,
                source: source,
                taskTitleSnapshot: projectTitle,
                detailTextSnapshot: summary
            ),
            in: context
        )
    }

    static func recordTaskUpdated(
        projectID: UUID,
        taskID: UUID,
        taskTitle: String,
        previousTitle: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        guard
            let summary = taskUpdateSummary(
                previousTitle: previousTitle,
                nextTitle: taskTitle
            )
        else { return }
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .taskUpdated),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .taskUpdated,
                source: source,
                taskID: taskID,
                taskTitleSnapshot: taskTitle,
                detailTextSnapshot: summary
            ),
            in: context
        )
    }

    static func recordTaskMoved(
        projectID: UUID,
        taskID: UUID,
        taskTitle: String,
        from sourceProjectTitle: String,
        to targetProjectTitle: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        let summary =
            "프로젝트 이동: \(normalizedInlineText(sourceProjectTitle)) → \(normalizedInlineText(targetProjectTitle))"
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .taskMoved),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .taskMoved,
                source: source,
                taskID: taskID,
                taskTitleSnapshot: taskTitle,
                detailTextSnapshot: summary
            ),
            in: context
        )
    }

    static func recordTaskDeleted(
        projectID: UUID,
        taskID: UUID,
        taskTitle: String,
        source: ProjectHistoryEventSource = .local,
        occurredAt: Date = .now,
        eventKey: String? = nil,
        in context: ModelContext
    ) {
        insertEvent(
            ProjectHistoryEvent(
                eventKey: eventKey ?? liveEventKey(for: .taskDeleted),
                projectID: projectID,
                occurredAt: occurredAt,
                kind: .taskDeleted,
                source: source,
                taskID: taskID,
                taskTitleSnapshot: taskTitle,
                detailTextSnapshot: "할일을 삭제했다."
            ),
            in: context
        )
    }

    static func backfillProjectCreatedKey(projectID: UUID) -> String {
        "backfill.projectCreated.\(projectID.uuidString)"
    }

    static func backfillTaskCreatedKey(taskID: UUID) -> String {
        "backfill.taskCreated.\(taskID.uuidString)"
    }

    static func backfillTaskCompletedKey(taskID: UUID, occurredAt: Date) -> String {
        "backfill.taskCompleted.\(taskID.uuidString).\(Int(occurredAt.timeIntervalSince1970))"
    }

    static func backfillAttachmentAddedKey(attachmentID: UUID) -> String {
        "backfill.attachmentAdded.\(attachmentID.uuidString)"
    }

    static func noteAdditionSummary(previous: String?, current: String) -> String? {
        let normalizedCurrent = normalizedNoteText(current)

        guard let previous else {
            return normalizedCurrent.isEmpty ? nil : normalizedCurrent
        }

        let normalizedPrevious = normalizedNoteText(previous)
        guard normalizedPrevious != normalizedCurrent else { return nil }

        let previousLines = normalizedNoteTextLines(normalizedPrevious)
        let currentLines = normalizedNoteTextLines(normalizedCurrent)
        let prefixCount = commonPrefixCount(previousLines, currentLines)
        let suffixCount = commonSuffixCount(
            Array(previousLines.dropFirst(prefixCount)),
            Array(currentLines.dropFirst(prefixCount))
        )

        let addedEndIndex = max(prefixCount, currentLines.count - suffixCount)
        let addedLines = Array(currentLines[prefixCount..<addedEndIndex])

        guard !addedLines.isEmpty else { return nil }
        return addedLines.joined(separator: "\n")
    }

    private static func liveEventKey(for kind: ProjectHistoryEventKind) -> String {
        "live.\(kind.rawValue).\(UUID().uuidString)"
    }

    private static func insertEvent(_ event: ProjectHistoryEvent, in context: ModelContext) {
        context.insert(event)
    }

    static func shouldBackfillCreationEvent(for task: TaskItem) -> Bool {
        if !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !task.reminderNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if task.startDate != nil || task.dueDate != nil { return true }
        if task.requiredWorkDays > 0 || task.completedWorkUnits > 0 { return true }
        if task.priority != 0 || task.isFlagged { return true }
        if let recurrenceRuleRaw = task.recurrenceRuleRaw,
           !recurrenceRuleRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if task.isCompleted || task.completionDate != nil { return true }
        if task.attachmentCount > 0 { return true }
        return false
    }

    private static func normalizedNoteText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        while normalized.hasSuffix("\n") {
            normalized.removeLast()
        }

        return normalized
    }

    private static func normalizedNoteTextLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.components(separatedBy: "\n")
    }

    private static func commonPrefixCount(_ lhs: [String], _ rhs: [String]) -> Int {
        let limit = min(lhs.count, rhs.count)
        var count = 0
        while count < limit && lhs[count] == rhs[count] {
            count += 1
        }
        return count
    }

    private static func commonSuffixCount(_ lhs: [String], _ rhs: [String]) -> Int {
        let limit = min(lhs.count, rhs.count)
        var count = 0
        while count < limit && lhs[lhs.count - 1 - count] == rhs[rhs.count - 1 - count] {
            count += 1
        }
        return count
    }

    private static func taskUpdateSummary(
        previousTitle: String,
        nextTitle: String
    ) -> String? {
        var parts: [String] = []

        let previousTitleText = normalizedInlineText(previousTitle)
        let nextTitleText = normalizedInlineText(nextTitle)
        if previousTitleText != nextTitleText {
            parts.append("제목: \(previousTitleText) → \(nextTitleText)")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    static func taskScheduleChangeSummary(
        previousState: ProjectTaskScheduleMutationSnapshot,
        nextState: ProjectTaskScheduleMutationSnapshot
    ) -> String? {
        let previousSummary = scheduleSnapshotSummary(previousState)
        let nextSummary = scheduleSnapshotSummary(nextState)
        guard previousSummary != nextSummary else { return nil }
        return "일정: \(previousSummary) → \(nextSummary)"
    }

    private static func projectTimelineChangeSummary(
        previousStartDate: Date?,
        previousDeadline: Date?,
        nextStartDate: Date?,
        nextDeadline: Date?
    ) -> String? {
        let previousSummary =
            "시작일 \(dateSummary(previousStartDate)) · 데드라인 \(dateSummary(previousDeadline))"
        let nextSummary =
            "시작일 \(dateSummary(nextStartDate)) · 데드라인 \(dateSummary(nextDeadline))"
        guard previousSummary != nextSummary else { return nil }
        return "\(previousSummary) → \(nextSummary)"
    }

    private static func scheduleSnapshotSummary(_ snapshot: ProjectTaskScheduleMutationSnapshot) -> String {
        let anchor = ReminderTaskDateCanonicalizer.unifiedDate(
            dueDate: snapshot.dueDate,
            startDate: snapshot.startDate
        )
        guard let anchor else { return "미정" }

        let base = snapshot.scheduleHasExplicitTime ? dateTimeSummary(anchor) : dateSummary(anchor)
        guard snapshot.scheduleHasExplicitTime else { return base }

        if let duration = snapshot.scheduledDurationMinutes, duration > 0 {
            return "\(base) · \(duration)분"
        }
        return base
    }

    private static func dateSummary(_ date: Date?) -> String {
        guard let date else { return "미정" }
        return dayFormatter.string(from: date)
    }

    private static func dateTimeSummary(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    private static func normalizedInlineText(_ text: String, emptyPlaceholder: String = "없음") -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? emptyPlaceholder : collapsed
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter
    }()
}
