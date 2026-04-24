import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID

    var reminderIdentifier: String?
    var reminderExternalIdentifier: String?
    var parentTaskID: UUID?
    var parentTaskRemoteExternalIdentifier: String?

    var title: String
    var isCompleted: Bool
    var completionDate: Date?
    var startDate: Date?
    var dueDate: Date?
    var scheduleHasExplicitTime: Bool = false
    var scheduledDurationMinutes: Int? = nil
    var priority: Int
    var recurrenceRuleRaw: String?
    var isFlagged: Bool

    var reminderNoteText: String
    var reminderRawPayloadRaw: String?
    var attachmentCount: Int
    var lastSyncedReminderTitle: String = ""
    var lastSyncedReminderNoteBody: String = ""
    var lastSyncedReminderModifiedAt: Date? = nil
    var reminderNoteConflictExcerpt: String? = nil

    var boardStageRaw: String
    var importanceRaw: String
    var rowOrder: Int
    var requiredWorkDays: Int = 0
    var completedWorkUnits: Int = 0
    var completedWorkUnitDatesRaw: String = ""
    var preparationScheduleOverridesRaw: String = ""

    var isArchived: Bool
    var archivedAt: Date?
    var isDirty: Bool

    var remoteLastModifiedAt: Date?
    var localUpdatedAt: Date
    var createdAt: Date

    @Relationship
    var project: Project?

    init(
        id: UUID = UUID(),
        reminderIdentifier: String? = nil,
        reminderExternalIdentifier: String? = nil,
        parentTaskID: UUID? = nil,
        parentTaskRemoteExternalIdentifier: String? = nil,
        title: String,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        startDate: Date? = nil,
        dueDate: Date? = nil,
        scheduleHasExplicitTime: Bool? = nil,
        scheduledDurationMinutes: Int? = nil,
        priority: Int = 0,
        recurrenceRuleRaw: String? = nil,
        isFlagged: Bool = false,
        reminderNoteText: String = "",
        reminderRawPayloadRaw: String? = nil,
        attachmentCount: Int = 0,
        boardStage: BoardStage = .now,
        importance: ImportanceLevel = .minor,
        rowOrder: Int = 0,
        requiredWorkDays: Int = 0,
        completedWorkUnits: Int = 0,
        completedWorkUnitDatesRaw: String = "",
        preparationScheduleOverridesRaw: String = "",
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        isDirty: Bool = true,
        remoteLastModifiedAt: Date? = nil,
        localUpdatedAt: Date = .now,
        createdAt: Date = .now,
        project: Project? = nil,
        lastSyncedReminderTitle: String = "",
        lastSyncedReminderNoteBody: String = "",
        lastSyncedReminderModifiedAt: Date? = nil,
        reminderNoteConflictExcerpt: String? = nil
    ) {
        self.id = id
        self.reminderIdentifier = reminderIdentifier
        self.reminderExternalIdentifier = reminderExternalIdentifier
        self.parentTaskID = parentTaskID
        self.parentTaskRemoteExternalIdentifier = parentTaskRemoteExternalIdentifier
        self.title = title
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        let normalizedReminderDateStorage = ReminderTaskDateCanonicalizer.normalizedStorage(
            dueDate: dueDate,
            startDate: startDate
        )
        self.startDate = normalizedReminderDateStorage.startDate
        self.dueDate = normalizedReminderDateStorage.dueDate
        let inferredAnchorDate = normalizedReminderDateStorage.dueDate
        let inferredHasExplicitTime =
            scheduleHasExplicitTime
            ?? Self.infersExplicitTime(from: inferredAnchorDate)
        self.scheduleHasExplicitTime = inferredHasExplicitTime
        if inferredHasExplicitTime, inferredAnchorDate != nil {
            let fallbackDuration = max(5, scheduledDurationMinutes ?? Self.defaultScheduledDurationMinutes)
            self.scheduledDurationMinutes = fallbackDuration
        } else {
            self.scheduledDurationMinutes = nil
        }
        self.priority = priority
        self.recurrenceRuleRaw = recurrenceRuleRaw
        self.isFlagged = isFlagged
        self.reminderNoteText = reminderNoteText
        self.reminderRawPayloadRaw = reminderRawPayloadRaw
        self.attachmentCount = attachmentCount
        self.lastSyncedReminderTitle = lastSyncedReminderTitle
        self.lastSyncedReminderNoteBody = lastSyncedReminderNoteBody
        self.lastSyncedReminderModifiedAt = lastSyncedReminderModifiedAt
        self.reminderNoteConflictExcerpt = reminderNoteConflictExcerpt
        self.boardStageRaw = boardStage.rawValue
        self.importanceRaw = importance.rawValue
        self.rowOrder = rowOrder
        self.requiredWorkDays = max(0, requiredWorkDays)
        self.completedWorkUnits = max(0, min(completedWorkUnits, max(0, requiredWorkDays)))
        self.completedWorkUnitDatesRaw = completedWorkUnitDatesRaw
        self.preparationScheduleOverridesRaw = preparationScheduleOverridesRaw
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.isDirty = isDirty
        self.remoteLastModifiedAt = remoteLastModifiedAt
        self.localUpdatedAt = localUpdatedAt
        self.createdAt = createdAt
        self.project = project
    }
}

extension TaskItem {
    static let defaultScheduledDurationMinutes = 30
    static let defaultPreparationTimeMinutes = 9 * 60

    struct CompletionMutationSnapshot: Equatable {
        var isCompleted: Bool
        var completionDate: Date?
        var startDate: Date?
        var dueDate: Date?
        var scheduleHasExplicitTime: Bool
        var scheduledDurationMinutes: Int?

        mutating func clearExplicitTime(calendar: Calendar = .autoupdatingCurrent) {
            let normalizedReminderDateStorage = ReminderTaskDateCanonicalizer.normalizedStorage(
                dueDate: dueDate,
                startDate: startDate
            )
            self.startDate = nil
            self.dueDate = normalizedReminderDateStorage.dueDate.map { calendar.startOfDay(for: $0) }
            scheduleHasExplicitTime = false
            scheduledDurationMinutes = nil
        }
    }

    struct PreparationScheduleOverride: Codable, Hashable {
        var isAllDay: Bool
        var timeMinutes: Int
        var durationMinutes: Int

        init(isAllDay: Bool, timeMinutes: Int, durationMinutes: Int) {
            self.isAllDay = isAllDay
            self.timeMinutes = timeMinutes
            self.durationMinutes = durationMinutes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
            timeMinutes = try container.decodeIfPresent(Int.self, forKey: .timeMinutes)
                ?? TaskItem.defaultPreparationTimeMinutes
            durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
                ?? TaskItem.defaultScheduledDurationMinutes
        }
    }

    static func infersExplicitTime(from date: Date?) -> Bool {
        guard let date else { return false }
        let calendar = Calendar.autoupdatingCurrent
        let dayStart = calendar.startOfDay(for: date)
        return !calendar.isDate(date, equalTo: dayStart, toGranularity: .second)
    }

    var belongsToArchivedProject: Bool {
        project?.isArchived ?? false
    }

    var normalizedParentTaskRemoteExternalIdentifier: String? {
        guard let value = parentTaskRemoteExternalIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    var reminderSyncBaseline: ReminderSyncBaseline {
        ReminderSyncBaseline(
            lastSyncedReminderTitle: lastSyncedReminderTitle,
            lastSyncedReminderNoteBody: lastSyncedReminderNoteBody,
            lastSyncedReminderModifiedAt: lastSyncedReminderModifiedAt,
            reminderNoteConflictExcerpt: reminderNoteConflictExcerpt
        )
    }

    @discardableResult
    func applyReminderSyncBaseline(_ baseline: ReminderSyncBaseline) -> Bool {
        var changed = false

        if lastSyncedReminderTitle != baseline.lastSyncedReminderTitle {
            lastSyncedReminderTitle = baseline.lastSyncedReminderTitle
            changed = true
        }
        if lastSyncedReminderNoteBody != baseline.lastSyncedReminderNoteBody {
            lastSyncedReminderNoteBody = baseline.lastSyncedReminderNoteBody
            changed = true
        }
        if lastSyncedReminderModifiedAt != baseline.lastSyncedReminderModifiedAt {
            lastSyncedReminderModifiedAt = baseline.lastSyncedReminderModifiedAt
            changed = true
        }
        if reminderNoteConflictExcerpt != baseline.reminderNoteConflictExcerpt {
            reminderNoteConflictExcerpt = baseline.reminderNoteConflictExcerpt
            changed = true
        }

        return changed
    }

    var isRecurringTask: Bool {
        !(recurrenceRuleRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var normalizedRequiredWorkDays: Int {
        max(0, requiredWorkDays)
    }

    var normalizedCompletedWorkUnits: Int {
        max(0, min(completedWorkUnits, normalizedRequiredWorkDays))
    }

    var normalizedScheduledDurationMinutes: Int? {
        guard let scheduledDurationMinutes else { return nil }
        return max(5, scheduledDurationMinutes)
    }

    var unifiedReminderDate: Date? {
        ReminderTaskDateCanonicalizer.unifiedDate(dueDate: dueDate, startDate: startDate)
    }

    var scheduledAnchorDate: Date? {
        unifiedReminderDate
    }

    var scheduledDay: Date? {
        guard let scheduledAnchorDate else { return nil }
        return Calendar.autoupdatingCurrent.startOfDay(for: scheduledAnchorDate)
    }

    var scheduledTimeMinutes: Int? {
        guard scheduleHasExplicitTime, let scheduledAnchorDate else { return nil }
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.hour, .minute],
            from: scheduledAnchorDate
        )
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    var scheduledEndDate: Date? {
        guard let scheduledAnchorDate, scheduleHasExplicitTime else { return nil }
        let durationMinutes = normalizedScheduledDurationMinutes ?? Self.defaultScheduledDurationMinutes
        return Calendar.autoupdatingCurrent.date(
            byAdding: .minute,
            value: durationMinutes,
            to: scheduledAnchorDate
        )
    }

    var isScheduledAllDay: Bool {
        scheduledAnchorDate != nil && !scheduleHasExplicitTime
    }

    var isScheduledTimed: Bool {
        scheduledAnchorDate != nil && scheduleHasExplicitTime
    }

    var completionMutationSnapshot: CompletionMutationSnapshot {
        let normalizedReminderDateStorage = ReminderTaskDateCanonicalizer.normalizedStorage(
            dueDate: dueDate,
            startDate: startDate
        )
        return CompletionMutationSnapshot(
            isCompleted: isCompleted,
            completionDate: completionDate,
            startDate: normalizedReminderDateStorage.startDate,
            dueDate: normalizedReminderDateStorage.dueDate,
            scheduleHasExplicitTime: scheduleHasExplicitTime,
            scheduledDurationMinutes: scheduledDurationMinutes
        )
    }

    var normalizedPreparationScheduleOverrides: [Int: PreparationScheduleOverride] {
        guard
            !preparationScheduleOverridesRaw.isEmpty,
            let data = preparationScheduleOverridesRaw.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([Int: PreparationScheduleOverride].self, from: data)
        else {
            return [:]
        }

        return decoded.filter { key, _ in key > 0 }
    }

    func preparationScheduleOverride(for targetCompletedUnits: Int) -> PreparationScheduleOverride? {
        normalizedPreparationScheduleOverrides[targetCompletedUnits]
    }

    func resolvedPreparationSchedule(for targetCompletedUnits: Int) -> PreparationScheduleOverride? {
        guard targetCompletedUnits > 0, targetCompletedUnits < normalizedRequiredWorkDays else {
            return nil
        }

        if let override = preparationScheduleOverride(for: targetCompletedUnits) {
            return PreparationScheduleOverride(
                isAllDay: override.isAllDay,
                timeMinutes: min(max(0, override.timeMinutes), 23 * 60 + 45),
                durationMinutes: max(5, override.durationMinutes)
            )
        }

        return PreparationScheduleOverride(
            isAllDay: true,
            timeMinutes: scheduledTimeMinutes ?? Self.defaultPreparationTimeMinutes,
            durationMinutes: normalizedScheduledDurationMinutes ?? Self.defaultScheduledDurationMinutes
        )
    }

    func setPreparationScheduleOverride(
        targetCompletedUnits: Int,
        isAllDay: Bool,
        timeMinutes: Int,
        durationMinutes: Int
    ) {
        guard targetCompletedUnits > 0 else { return }
        var overrides = normalizedPreparationScheduleOverrides
        overrides[targetCompletedUnits] = PreparationScheduleOverride(
            isAllDay: isAllDay,
            timeMinutes: min(max(0, timeMinutes), 23 * 60 + 45),
            durationMinutes: max(5, durationMinutes)
        )
        persistPreparationScheduleOverrides(overrides)
    }

    func trimPreparationScheduleOverrides() {
        let maxTarget = max(0, normalizedRequiredWorkDays - 1)
        let trimmed = normalizedPreparationScheduleOverrides.filter { key, _ in
            key > 0 && key <= maxTarget
        }
        persistPreparationScheduleOverrides(trimmed)
    }

    func applyCompletionMutationSnapshot(_ snapshot: CompletionMutationSnapshot) {
        isCompleted = snapshot.isCompleted
        completionDate = snapshot.completionDate
        startDate = snapshot.startDate
        dueDate = snapshot.dueDate
        scheduleHasExplicitTime = snapshot.scheduleHasExplicitTime
        scheduledDurationMinutes = snapshot.scheduledDurationMinutes
        normalizeReminderDateStorage()
    }

    static func completionMutationSnapshot(
        for task: TaskItem,
        isCompleted: Bool,
        completionDate: Date?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CompletionMutationSnapshot {
        var snapshot = task.completionMutationSnapshot
        snapshot.isCompleted = isCompleted
        snapshot.completionDate = isCompleted ? (completionDate ?? .now) : nil

        if isCompleted, task.isRecurringTask, snapshot.scheduleHasExplicitTime {
            snapshot.clearExplicitTime(calendar: calendar)
        }

        return snapshot
    }

    var normalizedCompletedWorkUnitDates: [Date] {
        let requiredCount = normalizedCompletedWorkUnits
        guard requiredCount > 0 else { return [] }

        var dates = decodedCompletedWorkUnitDates()
        if dates.count > requiredCount {
            dates = Array(dates.prefix(requiredCount))
        }

        if dates.count < requiredCount {
            let fallbackDate = completionDate ?? localUpdatedAt
            dates.append(contentsOf: Array(repeating: fallbackDate, count: requiredCount - dates.count))
        }

        return dates
    }

    @discardableResult
    func applyCompletedWorkUnits(_ targetCompletedUnits: Int, recordedAt: Date) -> Bool {
        let normalizedTarget = max(0, min(targetCompletedUnits, normalizedRequiredWorkDays))
        let previousCompletedUnits = normalizedCompletedWorkUnits
        guard previousCompletedUnits != normalizedTarget else { return false }

        var dates = normalizedCompletedWorkUnitDates
        if normalizedTarget > previousCompletedUnits {
            dates.append(
                contentsOf: Array(
                    repeating: recordedAt,
                    count: normalizedTarget - previousCompletedUnits
                )
            )
        } else {
            dates = Array(dates.prefix(normalizedTarget))
        }

        completedWorkUnits = normalizedTarget
        persistCompletedWorkUnitDates(dates)
        return true
    }

    func trimCompletedWorkUnitDates() {
        let trimmed = Array(normalizedCompletedWorkUnitDates.prefix(normalizedCompletedWorkUnits))
        persistCompletedWorkUnitDates(trimmed)
    }

    private func persistPreparationScheduleOverrides(_ overrides: [Int: PreparationScheduleOverride]) {
        guard !overrides.isEmpty else {
            preparationScheduleOverridesRaw = ""
            return
        }

        guard
            let data = try? JSONEncoder().encode(overrides),
            let raw = String(data: data, encoding: .utf8)
        else {
            return
        }

        preparationScheduleOverridesRaw = raw
    }

    private func decodedCompletedWorkUnitDates() -> [Date] {
        guard
            !completedWorkUnitDatesRaw.isEmpty,
            let data = completedWorkUnitDatesRaw.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([TimeInterval].self, from: data)
        else {
            return []
        }

        return decoded
            .filter(\.isFinite)
            .map(Date.init(timeIntervalSince1970:))
    }

    private func persistCompletedWorkUnitDates(_ dates: [Date]) {
        guard !dates.isEmpty else {
            completedWorkUnitDatesRaw = ""
            return
        }

        let encoded = dates.map(\.timeIntervalSince1970)
        guard
            let data = try? JSONEncoder().encode(encoded),
            let raw = String(data: data, encoding: .utf8)
        else {
            return
        }

        completedWorkUnitDatesRaw = raw
    }

    func applySchedule(
        day: Date?,
        timeMinutes: Int?,
        durationMinutes: Int?,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        guard let day else {
            startDate = nil
            dueDate = nil
            scheduleHasExplicitTime = false
            scheduledDurationMinutes = nil
            return
        }

        let normalizedDay = calendar.startOfDay(for: day)
        guard let timeMinutes else {
            startDate = nil
            dueDate = normalizedDay
            scheduleHasExplicitTime = false
            scheduledDurationMinutes = nil
            return
        }

        let boundedMinutes = min(max(0, timeMinutes), 23 * 60 + 59)
        let hours = boundedMinutes / 60
        let minutes = boundedMinutes % 60
        let timedDate =
            calendar.date(bySettingHour: hours, minute: minutes, second: 0, of: normalizedDay)
            ?? normalizedDay

        startDate = nil
        dueDate = timedDate
        scheduleHasExplicitTime = true
        scheduledDurationMinutes = max(
            5,
            durationMinutes ?? scheduledDurationMinutes ?? Self.defaultScheduledDurationMinutes
        )
    }

    func syncScheduleMetadata(
        hasExplicitTime: Bool,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let anchorDate = unifiedReminderDate
        let hasAnchorDate = anchorDate != nil
        scheduleHasExplicitTime = hasAnchorDate && hasExplicitTime

        guard hasAnchorDate else {
            startDate = nil
            dueDate = nil
            scheduledDurationMinutes = nil
            return
        }

        guard scheduleHasExplicitTime else {
            scheduledDurationMinutes = nil
            dueDate = anchorDate.map { calendar.startOfDay(for: $0) }
            startDate = nil
            return
        }

        dueDate = anchorDate
        startDate = nil
        scheduledDurationMinutes = max(5, scheduledDurationMinutes ?? Self.defaultScheduledDurationMinutes)
    }

    func backfillScheduleMetadataFromLegacyDates(calendar: Calendar = .autoupdatingCurrent) {
        let anchorDate = scheduledAnchorDate
        let hasExplicitTime = Self.infersExplicitTime(from: anchorDate)
        syncScheduleMetadata(hasExplicitTime: hasExplicitTime, calendar: calendar)
    }

    @discardableResult
    func normalizeReminderDateStorage() -> Bool {
        let normalizedReminderDateStorage = ReminderTaskDateCanonicalizer.normalizedStorage(
            dueDate: dueDate,
            startDate: startDate
        )
        let didChange =
            startDate != normalizedReminderDateStorage.startDate
            || dueDate != normalizedReminderDateStorage.dueDate
        startDate = normalizedReminderDateStorage.startDate
        dueDate = normalizedReminderDateStorage.dueDate
        return didChange
    }

    var boardStage: BoardStage {
        get { BoardStage(rawValue: boardStageRaw) ?? .now }
        set { boardStageRaw = newValue.rawValue }
    }

    var importance: ImportanceLevel {
        get { ImportanceLevel(rawValue: importanceRaw) ?? .minor }
        set { importanceRaw = newValue.rawValue }
    }
}
