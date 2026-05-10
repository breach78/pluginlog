import SwiftUI

struct WorkspaceCalendarEventEditPanelTarget: Equatable, Sendable {
  let eventID: String
  let event: ScheduleCalendarEvent
  let initialFields: ScheduleCalendarEventEditFields
}

@MainActor
private final class ScheduleCalendarEventAutoSaveCoordinator: ObservableObject {
  private var task: Task<Void, Never>?

  func schedule(
    delayNanoseconds: UInt64,
    operation: @escaping @MainActor () async -> Void
  ) {
    cancel()
    task = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: delayNanoseconds)
      } catch {
        return
      }
      guard let self else { return }
      task = nil
      await operation()
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }

  deinit {
    task?.cancel()
  }
}

struct ScheduleCalendarEventEditPanelContent: View {
  let event: ScheduleCalendarEvent
  let initialFields: ScheduleCalendarEventEditFields
  let loadFields: () async -> ScheduleCalendarEventEditFields
  let saveFields:
    (ScheduleCalendarEventEditFields, ScheduleCalendarRecurringEditScope) async throws
      -> ScheduleCalendarEventEditFields
  let onCancel: () -> Void

  @State private var title: String
  @State private var noteText: String
  @State private var selectedDate: Date
  @State private var selectedEndDate: Date
  @State private var isStartDatePickerPresented = false
  @State private var isEndDatePickerPresented = false
  @State private var hasTime: Bool
  @State private var selectedStartTime: Date
  @State private var selectedEndTime: Date
  @State private var recurringScope: ScheduleCalendarRecurringEditScope = .thisEvent
  @State private var lastCommittedFields: ScheduleCalendarEventEditFields
  @State private var isSaving = false
  @State private var saveAgainAfterCurrent = false
  @State private var isApplyingFields = false
  @State private var errorText: String?
  @StateObject private var autoSaveCoordinator = ScheduleCalendarEventAutoSaveCoordinator()

  private let calendar = Calendar.autoupdatingCurrent
  private static let autoSaveDelayNanoseconds: UInt64 = 1_500_000_000

  init(
    event: ScheduleCalendarEvent,
    initialFields: ScheduleCalendarEventEditFields,
    loadFields: @escaping () async -> ScheduleCalendarEventEditFields,
    saveFields: @escaping (
      ScheduleCalendarEventEditFields,
      ScheduleCalendarRecurringEditScope
    ) async throws -> ScheduleCalendarEventEditFields,
    onCancel: @escaping () -> Void
  ) {
    self.event = event
    self.initialFields = initialFields
    self.loadFields = loadFields
    self.saveFields = saveFields
    self.onCancel = onCancel
    _title = State(initialValue: initialFields.title)
    _noteText = State(initialValue: initialFields.noteText)
    _selectedDate = State(initialValue: initialFields.day)
    _selectedEndDate = State(initialValue: initialFields.endDay)
    _hasTime = State(initialValue: !initialFields.isAllDay)
    _selectedStartTime = State(initialValue: Self.timeDate(minutes: initialFields.startMinutes))
    _selectedEndTime = State(initialValue: Self.timeDate(minutes: initialFields.endMinutes ?? 10 * 60))
    _lastCommittedFields = State(initialValue: Self.normalizedFields(initialFields))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if !event.canEditTiming {
            Text(event.editTimingRestrictionReason ?? "이 캘린더 이벤트는 수정할 수 없습니다.")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if event.isRecurring {
            recurringScopeSection
              .disabled(!event.canEditTiming)
          }

          titleSection
            .disabled(!event.canEditTiming)
          noteSection
            .disabled(!event.canEditTiming)
          scheduleSection
            .disabled(!event.canEditTiming)

          if let message = validationText ?? errorText {
            Text(message)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(validationText == nil ? .red : .orange)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else if isSaving {
            Text("저장 중")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
      }
    }
    .background(Color(nsColor: NSColor(calibratedWhite: 1, alpha: 1)))
    .onChange(of: title) { _, _ in scheduleAutoSave() }
    .onChange(of: noteText) { _, _ in scheduleAutoSave() }
    .onChange(of: selectedDate) { _, _ in
      normalizeEndDateAfterStartDateChange()
      scheduleAutoSave()
    }
    .onChange(of: selectedEndDate) { _, _ in
      normalizeEndDateAfterStartDateChange()
      scheduleAutoSave()
    }
    .onChange(of: hasTime) { _, enabled in
      if enabled {
        normalizeEndTimeAfterStartChange()
      }
      scheduleAutoSave()
    }
    .onChange(of: selectedStartTime) { _, _ in
      normalizeEndTimeAfterStartChange()
      scheduleAutoSave()
    }
    .onChange(of: selectedEndTime) { _, _ in scheduleAutoSave() }
    .onChange(of: recurringScope) { _, _ in scheduleAutoSave() }
    .task {
      let fields = await loadFields()
      apply(fields)
    }
    .onDisappear {
      flushPendingChangesOnDisappear()
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Text("일정 편집")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(.primary)

      Spacer(minLength: 0)

      Button {
        closeEditor()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 20, weight: .semibold))
          .frame(width: 34, height: 34)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("닫기")
    }
    .padding(.leading, 28)
    .padding(.trailing, 22)
    .padding(.top, 34)
    .padding(.bottom, 22)
  }

  private var recurringScopeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("반복 일정")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)

      Picker("적용 범위", selection: $recurringScope) {
        Text(ScheduleCalendarRecurringEditScope.thisEvent.title)
          .tag(ScheduleCalendarRecurringEditScope.thisEvent)
        Text(ScheduleCalendarRecurringEditScope.futureEvents.title)
          .tag(ScheduleCalendarRecurringEditScope.futureEvents)
      }
      .pickerStyle(.segmented)
    }
  }

  private var titleSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("제목")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)

      TextField("", text: $title)
        .font(.system(size: 24, weight: .bold))
        .textFieldStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(fieldBackground)
    }
  }

  private var noteSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("내용")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)

      TextEditor(text: $noteText)
        .font(.system(size: 17))
        .scrollContentBackground(.hidden)
        .frame(minHeight: 170)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(fieldBackground)
    }
  }

  private var scheduleSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 18) {
        VStack(alignment: .leading, spacing: 10) {
          Text("날짜")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)

          dateControl(
            title: "시작",
            date: $selectedDate,
            isPresented: $isStartDatePickerPresented
          )

          dateControl(
            title: "끝",
            date: $selectedEndDate,
            isPresented: $isEndDatePickerPresented
          )
        }
        .frame(width: 260, alignment: .topLeading)

        VStack(alignment: .leading, spacing: 10) {
          Toggle("시간 설정", isOn: $hasTime)
            .font(.system(size: 15, weight: .semibold))
            .toggleStyle(.checkbox)

          if hasTime {
            DatePicker("시작", selection: $selectedStartTime, displayedComponents: .hourAndMinute)
              .font(.system(size: 15))
            DatePicker("끝", selection: $selectedEndTime, displayedComponents: .hourAndMinute)
              .font(.system(size: 15))
          } else {
            Text("종일")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 2)
      }
    }
  }

  private func dateControl(
    title: String,
    date: Binding<Date>,
    isPresented: Binding<Bool>
  ) -> some View {
    Button {
      isPresented.wrappedValue = true
    } label: {
      HStack(spacing: 8) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 34, alignment: .leading)
        Image(systemName: "calendar")
          .font(.system(size: 13, weight: .semibold))
        Text(date.wrappedValue.formatted(.dateTime.year().month(.wide).day()))
          .font(.system(size: 15, weight: .medium))
          .lineLimit(1)
        Spacer(minLength: 0)
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .calendarEventCompactControlBackground()
    }
    .buttonStyle(.plain)
    .foregroundStyle(Color.primary)
    .popover(isPresented: isPresented, arrowEdge: .bottom) {
      DatePicker("", selection: date, displayedComponents: .date)
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(12)
        .frame(width: 284, alignment: .leading)
        .background(CalendarEventEditFieldStyle.panelBackgroundColor)
    }
  }

  private var fieldBackground: some View {
    Rectangle()
      .fill(Color(nsColor: NSColor(calibratedWhite: 0.92, alpha: 1)))
  }

  private var validationText: String? {
    let fields = currentFields()
    guard event.canEditTiming else { return nil }
    guard !fields.title.isEmpty else { return "제목을 입력해야 저장됩니다." }
    guard !fields.isAllDay else { return nil }
    guard let startMinutes = fields.startMinutes, let endMinutes = fields.endMinutes else {
      return "시작과 끝 시간을 확인해야 저장됩니다."
    }
    guard fields.endDay > fields.day || endMinutes > startMinutes else {
      return "끝 시간은 시작 시간보다 뒤여야 합니다."
    }
    return nil
  }

  private func apply(_ fields: ScheduleCalendarEventEditFields) {
    isApplyingFields = true
    defer { isApplyingFields = false }
    autoSaveCoordinator.cancel()
    let normalized = Self.normalizedFields(fields)
    title = normalized.title
    noteText = normalized.noteText
    selectedDate = normalized.day
    selectedEndDate = normalized.endDay
    hasTime = !normalized.isAllDay
    selectedStartTime = Self.timeDate(minutes: normalized.startMinutes)
    selectedEndTime = Self.timeDate(minutes: normalized.endMinutes ?? 10 * 60)
    lastCommittedFields = normalized
  }

  private func closeEditor() {
    Task { @MainActor in
      guard await flushPendingChanges() else { return }
      onCancel()
    }
  }

  @MainActor
  private func scheduleAutoSave() {
    guard !isApplyingFields, event.canEditTiming else { return }
    guard validationText == nil else { return }
    guard shouldSave(currentFields()) else { return }
    autoSaveCoordinator.schedule(delayNanoseconds: Self.autoSaveDelayNanoseconds) {
      _ = await savePendingChanges()
    }
  }

  @MainActor
  private func flushPendingChanges() async -> Bool {
    autoSaveCoordinator.cancel()
    return await savePendingChanges()
  }

  private func flushPendingChangesOnDisappear() {
    autoSaveCoordinator.cancel()
    Task { @MainActor in
      _ = await savePendingChanges(afterCurrent: true)
    }
  }

  @MainActor
  private func savePendingChanges(afterCurrent: Bool = false) async -> Bool {
    guard event.canEditTiming else { return true }
    guard validationText == nil else { return true }
    guard !isSaving else {
      if afterCurrent {
        saveAgainAfterCurrent = true
      } else {
        scheduleAutoSave()
      }
      return true
    }

    let fields = currentFields()
    guard shouldSave(fields) else { return true }
    isSaving = true
    errorText = nil
    do {
      let savedFields = try await saveFields(fields, event.isRecurring ? recurringScope : .thisEvent)
      lastCommittedFields = Self.normalizedFields(savedFields)
      isSaving = false
      let shouldSaveImmediately = saveAgainAfterCurrent
      saveAgainAfterCurrent = false
      if shouldSaveImmediately {
        return await savePendingChanges(afterCurrent: true)
      }
      if currentFields() != lastCommittedFields {
        scheduleAutoSave()
      }
      return true
    } catch {
      isSaving = false
      saveAgainAfterCurrent = false
      errorText = error.localizedDescription
      return false
    }
  }

  private func shouldSave(_ fields: ScheduleCalendarEventEditFields) -> Bool {
    fields != lastCommittedFields
  }

  private func currentFields() -> ScheduleCalendarEventEditFields {
    Self.normalizedFields(
      ScheduleCalendarEventEditFields(
        title: title,
        noteText: noteText,
        day: calendar.startOfDay(for: selectedDate),
        endDay: calendar.startOfDay(for: selectedEndDate),
        isAllDay: !hasTime,
        startMinutes: hasTime ? Self.timeMinutes(from: selectedStartTime) : nil,
        endMinutes: hasTime ? Self.timeMinutes(from: selectedEndTime) : nil
      )
    )
  }

  private func normalizeEndTimeAfterStartChange() {
    guard hasTime else { return }
    guard calendar.startOfDay(for: selectedDate) == calendar.startOfDay(for: selectedEndDate) else {
      return
    }
    let startMinutes = Self.timeMinutes(from: selectedStartTime)
    let endMinutes = Self.timeMinutes(from: selectedEndTime)
    guard endMinutes <= startMinutes else { return }
    selectedEndTime = Self.timeDate(minutes: min(startMinutes + 60, 23 * 60 + 59))
  }

  private func normalizeEndDateAfterStartDateChange() {
    let startDay = calendar.startOfDay(for: selectedDate)
    let endDay = calendar.startOfDay(for: selectedEndDate)
    guard endDay < startDay else { return }
    selectedEndDate = startDay
  }

  static func normalizedFields(
    _ fields: ScheduleCalendarEventEditFields
  ) -> ScheduleCalendarEventEditFields {
    let normalizedTitle = fields.title
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedNoteText =
      fields.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? ""
      : fields.noteText
    let normalizedDay = Calendar.autoupdatingCurrent.startOfDay(for: fields.day)
    let normalizedEndDay = max(
      normalizedDay,
      Calendar.autoupdatingCurrent.startOfDay(for: fields.endDay)
    )
    if fields.isAllDay {
      return ScheduleCalendarEventEditFields(
        title: normalizedTitle,
        noteText: normalizedNoteText,
        day: normalizedDay,
        endDay: normalizedEndDay,
        isAllDay: true,
        startMinutes: nil,
        endMinutes: nil
      )
    }

    return ScheduleCalendarEventEditFields(
      title: normalizedTitle,
      noteText: normalizedNoteText,
      day: normalizedDay,
      endDay: normalizedEndDay,
      isAllDay: false,
      startMinutes: fields.startMinutes.map { min(max(0, $0), 23 * 60 + 59) },
      endMinutes: fields.endMinutes.map { min(max(0, $0), 23 * 60 + 59) }
    )
  }

  static func editFields(for event: ScheduleCalendarEvent) -> ScheduleCalendarEventEditFields {
    let calendar = Calendar.autoupdatingCurrent
    let startMinutes = timeMinutes(from: event.startDate)
    let endMinutes = timeMinutes(from: event.endDate)
    let startDay = calendar.startOfDay(for: event.startDate)
    let endDay: Date
    if event.isAllDay {
      let exclusiveEndDay = calendar.startOfDay(for: event.endDate)
      let visibleEndDay =
        calendar.date(byAdding: .day, value: -1, to: exclusiveEndDay)
        ?? startDay
      endDay = max(startDay, visibleEndDay)
    } else {
      endDay = max(startDay, calendar.startOfDay(for: event.endDate))
    }
    return ScheduleCalendarEventEditFields(
      title: event.title,
      noteText: event.notes,
      day: startDay,
      endDay: endDay,
      isAllDay: event.isAllDay,
      startMinutes: event.isAllDay ? nil : startMinutes,
      endMinutes: event.isAllDay ? nil : endMinutes
    )
  }

  private static func timeDate(minutes: Int?) -> Date {
    let boundedMinutes = min(max(0, minutes ?? 9 * 60), 23 * 60 + 59)
    return Calendar.autoupdatingCurrent.date(
      bySettingHour: boundedMinutes / 60,
      minute: boundedMinutes % 60,
      second: 0,
      of: .now
    ) ?? .now
  }

  private static func timeMinutes(from date: Date) -> Int {
    let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }
}

private enum CalendarEventEditFieldStyle {
  static let panelBackgroundColor = Color(
    nsColor: NSColor(calibratedWhite: 1, alpha: 1)
  )

  static let controlBackgroundColor = Color(
    nsColor: NSColor(calibratedWhite: 0.985, alpha: 1)
  )
}

private struct CalendarEventEditCompactControlBackground: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 10)
      .frame(height: 32)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(CalendarEventEditFieldStyle.controlBackgroundColor)
      )
  }
}

private extension View {
  func calendarEventCompactControlBackground() -> some View {
    modifier(CalendarEventEditCompactControlBackground())
  }
}
