import SwiftUI

struct ProjectOutlineSchedulePopover: View {
  let task: TimelineProjectListWindowSnapshot.Task
  let initialFields: RetainedTaskEditFields
  let loadFields: () async -> RetainedTaskEditFields
  let saveFields: (RetainedTaskEditFields) async throws -> Void
  let recurringCompletionCount: Int
  let projectColor: Color

  @State private var selectedDate: Date
  @State private var hasDate: Bool
  @State private var selectedTimeMinutes: Int
  @State private var durationMinutes: Int
  @State private var recurrenceDescriptor: ReminderRecurrenceDescriptor
  @State private var isSaving = false
  @State private var errorText: String?
  @State private var saveTask: Task<Void, Never>?
  @State private var didLoadFields = false

  private let calendar = Calendar.autoupdatingCurrent
  private static let noTimeTag = -1
  private static let defaultDurationMinutes = 30

  init(
    task: TimelineProjectListWindowSnapshot.Task,
    initialFields: RetainedTaskEditFields,
    loadFields: @escaping () async -> RetainedTaskEditFields,
    saveFields: @escaping (RetainedTaskEditFields) async throws -> Void,
    recurringCompletionCount: Int,
    projectColor: Color
  ) {
    self.task = task
    self.initialFields = initialFields
    self.loadFields = loadFields
    self.saveFields = saveFields
    self.recurringCompletionCount = recurringCompletionCount
    self.projectColor = projectColor
    _selectedDate = State(initialValue: initialFields.day ?? .now)
    _hasDate = State(initialValue: initialFields.day != nil)
    _selectedTimeMinutes = State(initialValue: initialFields.timeMinutes ?? Self.noTimeTag)
    _durationMinutes = State(
      initialValue: TimelineTaskEditDurationPolicy.normalized(
        initialFields.durationMinutes ?? Self.defaultDurationMinutes
      )
    )
    _recurrenceDescriptor = State(
      initialValue: ReminderRecurrenceDescriptor.parse(initialFields.recurrenceRuleRaw)
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      DatePicker("", selection: dateBinding, displayedComponents: .date)
        .datePickerStyle(.graphical)
        .labelsHidden()
        .tint(projectColor)

      HStack(spacing: 8) {
        Picker("", selection: timeBinding) {
          Text("시간 없음").tag(Self.noTimeTag)
          ForEach(timeOptions, id: \.self) { minutes in
            Text(timeText(minutes)).tag(minutes)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .taskEditCompactControlBackground()

        Picker("", selection: durationBinding) {
          ForEach(durationPickerOptions, id: \.self) { minutes in
            Text(TimelineTaskEditDurationPolicy.displayText(minutes)).tag(minutes)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .taskEditCompactControlBackground()
        .disabled(selectedTimeMinutes == Self.noTimeTag)
      }

      TaskEditRecurrenceControl(
        descriptor: recurrenceBinding,
        selectedDate: calendar.startOfDay(for: selectedDate),
        calendar: calendar
      )

      HStack(spacing: 8) {
        Button("날짜 지우기") {
          hasDate = false
          selectedTimeMinutes = Self.noTimeTag
          recurrenceDescriptor = .none
          scheduleSave()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.secondary)

        Spacer()

        if isSaving {
          ProgressView()
            .controlSize(.small)
        } else if recurringCompletionCount > 0 {
          Text("\(recurringCompletionCount)")
            .monospacedDigit()
            .foregroundStyle(projectColor)
        }
      }

      if let errorText {
        Text(errorText)
          .font(projectOutlineSchedulePopoverFont)
          .foregroundStyle(.red)
          .lineLimit(2)
      }
    }
    .font(projectOutlineSchedulePopoverFont)
    .padding(10)
    .frame(width: 320, alignment: .leading)
    .background(TaskEditFieldStyle.panelBackgroundColor)
    .task(id: task.id) {
      await loadLatestFieldsIfNeeded()
    }
    .onDisappear {
      saveTask?.cancel()
      saveTask = nil
    }
  }

  private var dateBinding: Binding<Date> {
    Binding(
      get: { selectedDate },
      set: { nextDate in
        selectedDate = nextDate
        hasDate = true
        scheduleSave()
      }
    )
  }

  private var timeBinding: Binding<Int> {
    Binding(
      get: { selectedTimeMinutes },
      set: { nextMinutes in
        selectedTimeMinutes = nextMinutes
        if nextMinutes != Self.noTimeTag {
          hasDate = true
          durationMinutes = TimelineTaskEditDurationPolicy.normalized(durationMinutes)
        }
        scheduleSave()
      }
    )
  }

  private var durationBinding: Binding<Int> {
    Binding(
      get: { TimelineTaskEditDurationPolicy.normalized(durationMinutes) },
      set: { nextMinutes in
        durationMinutes = TimelineTaskEditDurationPolicy.normalized(nextMinutes)
        if selectedTimeMinutes != Self.noTimeTag {
          hasDate = true
        }
        scheduleSave()
      }
    )
  }

  private var recurrenceBinding: Binding<ReminderRecurrenceDescriptor> {
    Binding(
      get: { recurrenceDescriptor },
      set: { nextDescriptor in
        recurrenceDescriptor = nextDescriptor
        if nextDescriptor != .none, !nextDescriptor.isUnsupported {
          hasDate = true
        }
        scheduleSave()
      }
    )
  }

  private var durationPickerOptions: [Int] {
    TimelineTaskEditDurationPolicy.pickerOptions(
      including: TimelineTaskEditDurationPolicy.normalized(durationMinutes)
    )
  }

  private var timeOptions: [Int] {
    Array(stride(from: 0, through: 23 * 60 + 45, by: 15))
  }

  private func timeText(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }

  private func scheduleSave() {
    saveTask?.cancel()
    saveTask = Task { @MainActor in
      await saveCurrentSchedule()
    }
  }

  @MainActor
  private func loadLatestFieldsIfNeeded() async {
    guard !didLoadFields else { return }
    didLoadFields = true
    let fields = await loadFields()
    guard !isSaving else { return }
    apply(fields)
  }

  private func apply(_ fields: RetainedTaskEditFields) {
    selectedDate = fields.day ?? .now
    hasDate = fields.day != nil
    selectedTimeMinutes = fields.timeMinutes ?? Self.noTimeTag
    durationMinutes = TimelineTaskEditDurationPolicy.normalized(
      fields.durationMinutes ?? Self.defaultDurationMinutes
    )
    recurrenceDescriptor = ReminderRecurrenceDescriptor.parse(fields.recurrenceRuleRaw)
  }

  @MainActor
  private func saveCurrentSchedule() async {
    isSaving = true
    errorText = nil
    do {
      var fields = await loadFields()
      fields.day = hasDate ? calendar.startOfDay(for: selectedDate) : nil
      fields.timeMinutes = hasDate && selectedTimeMinutes != Self.noTimeTag
        ? selectedTimeMinutes
        : nil
      fields.durationMinutes = TimelineTaskEditDurationPolicy.savedDuration(
        hasDate: fields.day != nil,
        hasTime: fields.timeMinutes != nil,
        durationMinutes: durationMinutes
      )
      fields.recurrenceRuleRaw = recurrenceDescriptor.rawValue
      fields.updatesRecurrence = true
      try await saveFields(fields)
      isSaving = false
    } catch {
      isSaving = false
      errorText = error.localizedDescription
    }
  }
}

private let projectOutlineSchedulePopoverFont = Font.custom(
  "SansMonoCJKFinalDraft-Bold",
  size: 12
)
