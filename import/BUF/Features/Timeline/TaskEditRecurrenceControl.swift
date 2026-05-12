import SwiftUI

enum TaskEditRecurrenceKind: String, CaseIterable, Identifiable {
  case none
  case daily
  case weekly
  case monthlyByDay
  case monthlyByWeekday
  case yearly
  case unsupported

  var id: String { rawValue }

  var title: String {
    switch self {
    case .none: "없음"
    case .daily: "매일"
    case .weekly: "매주"
    case .monthlyByDay: "매월 날짜"
    case .monthlyByWeekday: "매월 요일"
    case .yearly: "매년"
    case .unsupported: "복잡한 반복"
    }
  }
}

struct TaskEditRecurrenceControl: View {
  @Binding var descriptor: ReminderRecurrenceDescriptor
  let selectedDate: Date
  let calendar: Calendar

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        Text("반복")
          .font(TaskEditTypography.controlFont)
          .frame(width: 88, alignment: .leading)

        Picker("", selection: kindBinding) {
          ForEach(availableKinds) { kind in
            Text(kind.title).tag(kind)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .taskEditCompactControlBackground()
      }

      if !descriptor.isUnsupported, kindBinding.wrappedValue != .none {
        intervalRow
      }

      switch descriptor {
      case .weekly:
        weekdayRow
      case .monthlyByDay, .monthly:
        monthDayRow
      case .monthlyByWeekday:
        monthWeekdayRow
      default:
        EmptyView()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .tint(TaskEditFieldStyle.softAccentColor)
  }

  private var availableKinds: [TaskEditRecurrenceKind] {
    descriptor.isUnsupported
      ? TaskEditRecurrenceKind.allCases
      : TaskEditRecurrenceKind.allCases.filter { $0 != .unsupported }
  }

  private var intervalRow: some View {
    HStack(alignment: .center, spacing: 10) {
      Text("간격")
        .font(TaskEditTypography.controlFont)
        .frame(width: 88, alignment: .leading)

      HStack(spacing: 8) {
        TextField("간격", value: intervalBinding, format: .number)
          .textFieldStyle(.plain)
          .font(TaskEditTypography.controlFont)
          .monospacedDigit()
          .multilineTextAlignment(.trailing)
          .frame(width: 44)
        Text(intervalUnitText)
          .font(TaskEditTypography.controlFont)
          .foregroundStyle(.secondary)
        Stepper("", value: intervalBinding, in: 1...99)
          .labelsHidden()
          .frame(width: 54)
      }
      .taskEditCompactControlBackground()
    }
  }

  private var weekdayRow: some View {
    HStack(alignment: .center, spacing: 10) {
      Text("요일")
        .font(TaskEditTypography.controlFont)
        .frame(width: 88, alignment: .leading)

      HStack(spacing: 4) {
        ForEach(Self.weekdayValues, id: \.self) { weekday in
          Button(Self.weekdayTitle(weekday)) {
            toggleWeekday(weekday)
          }
          .buttonStyle(.plain)
          .font(TaskEditTypography.controlFont)
          .foregroundStyle(weeklyWeekdays.contains(weekday) ? Color.primary : Color.secondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 4)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(
                weeklyWeekdays.contains(weekday)
                  ? TaskEditFieldStyle.softAccentColor
                  : Color.clear
              )
          )
        }
      }
      .taskEditCompactControlBackground()
    }
  }

  private var monthDayRow: some View {
    HStack(alignment: .center, spacing: 10) {
      Text("일")
        .font(TaskEditTypography.controlFont)
        .frame(width: 88, alignment: .leading)

      HStack(spacing: 8) {
        TextField("일", value: monthDayBinding, format: .number)
          .textFieldStyle(.plain)
          .font(TaskEditTypography.controlFont)
          .monospacedDigit()
          .multilineTextAlignment(.trailing)
          .frame(width: 44)
        Text("일")
          .font(TaskEditTypography.controlFont)
          .foregroundStyle(.secondary)
        Stepper("", value: monthDayBinding, in: 1...31)
          .labelsHidden()
          .frame(width: 54)
      }
      .taskEditCompactControlBackground()
    }
  }

  private var monthWeekdayRow: some View {
    HStack(alignment: .center, spacing: 10) {
      Text("기준")
        .font(TaskEditTypography.controlFont)
        .frame(width: 88, alignment: .leading)

      HStack(spacing: 8) {
        Picker("", selection: monthOrdinalBinding) {
          ForEach(Self.monthOrdinals, id: \.self) { ordinal in
            Text(Self.monthOrdinalTitle(ordinal)).tag(ordinal)
          }
        }
        .labelsHidden()
        .frame(width: 96)

        Picker("", selection: monthWeekdayBinding) {
          ForEach(Self.weekdayValues, id: \.self) { weekday in
            Text(Self.weekdayTitle(weekday)).tag(weekday)
          }
        }
        .labelsHidden()
        .frame(width: 88)
      }
      .taskEditCompactControlBackground()
    }
  }

  private var kindBinding: Binding<TaskEditRecurrenceKind> {
    Binding(
      get: { kind(for: descriptor) },
      set: { nextKind in
        descriptor = defaultDescriptor(for: nextKind)
      }
    )
  }

  private var intervalBinding: Binding<Int> {
    Binding(
      get: { interval(for: descriptor) },
      set: { nextValue in
        setInterval(nextValue)
      }
    )
  }

  private var monthDayBinding: Binding<Int> {
    Binding(
      get: { monthlyDays.first ?? selectedMonthDay },
      set: { nextValue in
        descriptor = .monthlyByDay(
          interval: interval(for: descriptor),
          days: [min(31, max(1, nextValue))]
        )
      }
    )
  }

  private var monthOrdinalBinding: Binding<Int> {
    Binding(
      get: { monthlyWeekdays.first?.weekNumber ?? selectedWeekNumber },
      set: { nextValue in
        descriptor = .monthlyByWeekday(
          interval: interval(for: descriptor),
          weekdays: [
            ReminderRecurrenceWeekdayOrdinal(
              weekday: monthlyWeekdays.first?.weekday ?? selectedWeekday,
              weekNumber: nextValue
            )
          ]
        )
      }
    )
  }

  private var monthWeekdayBinding: Binding<Int> {
    Binding(
      get: { monthlyWeekdays.first?.weekday ?? selectedWeekday },
      set: { nextValue in
        descriptor = .monthlyByWeekday(
          interval: interval(for: descriptor),
          weekdays: [
            ReminderRecurrenceWeekdayOrdinal(
              weekday: nextValue,
              weekNumber: monthlyWeekdays.first?.weekNumber ?? selectedWeekNumber
            )
          ]
        )
      }
    )
  }

  private var intervalUnitText: String {
    switch kind(for: descriptor) {
    case .daily: "일마다"
    case .weekly: "주마다"
    case .monthlyByDay, .monthlyByWeekday: "개월마다"
    case .yearly: "년마다"
    case .none, .unsupported: ""
    }
  }

  private var weeklyWeekdays: [Int] {
    if case .weekly(_, let weekdays) = descriptor {
      return weekdays
    }
    return [selectedWeekday]
  }

  private var monthlyDays: [Int] {
    if case .monthlyByDay(_, let days) = descriptor {
      return days
    }
    return [selectedMonthDay]
  }

  private var monthlyWeekdays: [ReminderRecurrenceWeekdayOrdinal] {
    if case .monthlyByWeekday(_, let weekdays) = descriptor {
      return weekdays
    }
    return [ReminderRecurrenceWeekdayOrdinal(weekday: selectedWeekday, weekNumber: selectedWeekNumber)]
  }

  private var selectedWeekday: Int {
    calendar.component(.weekday, from: selectedDate)
  }

  private var selectedMonthDay: Int {
    calendar.component(.day, from: selectedDate)
  }

  private var selectedWeekNumber: Int {
    max(1, min(5, ((selectedMonthDay - 1) / 7) + 1))
  }

  private func kind(for descriptor: ReminderRecurrenceDescriptor) -> TaskEditRecurrenceKind {
    switch descriptor {
    case .none: .none
    case .daily: .daily
    case .weekly: .weekly
    case .monthly, .monthlyByDay: .monthlyByDay
    case .monthlyByWeekday: .monthlyByWeekday
    case .yearly: .yearly
    case .unsupported: .unsupported
    }
  }

  private func defaultDescriptor(for kind: TaskEditRecurrenceKind) -> ReminderRecurrenceDescriptor {
    switch kind {
    case .none:
      return .none
    case .daily:
      return .daily(interval: interval(for: descriptor))
    case .weekly:
      return .weekly(interval: interval(for: descriptor), weekdays: [selectedWeekday])
    case .monthlyByDay:
      return .monthlyByDay(interval: interval(for: descriptor), days: [selectedMonthDay])
    case .monthlyByWeekday:
      return .monthlyByWeekday(
        interval: interval(for: descriptor),
        weekdays: [
          ReminderRecurrenceWeekdayOrdinal(weekday: selectedWeekday, weekNumber: selectedWeekNumber)
        ]
      )
    case .yearly:
      return .yearly(interval: interval(for: descriptor))
    case .unsupported:
      return descriptor
    }
  }

  private func interval(for descriptor: ReminderRecurrenceDescriptor) -> Int {
    switch descriptor {
    case .none, .unsupported:
      return 1
    case .daily(let interval),
      .weekly(let interval, _),
      .monthly(let interval),
      .monthlyByDay(let interval, _),
      .monthlyByWeekday(let interval, _),
      .yearly(let interval):
      return max(1, interval)
    }
  }

  private func setInterval(_ value: Int) {
    let nextInterval = max(1, value)
    switch descriptor {
    case .none, .unsupported:
      return
    case .daily:
      descriptor = .daily(interval: nextInterval)
    case .weekly(_, let weekdays):
      descriptor = .weekly(interval: nextInterval, weekdays: weekdays.isEmpty ? [selectedWeekday] : weekdays)
    case .monthly:
      descriptor = .monthly(interval: nextInterval)
    case .monthlyByDay(_, let days):
      descriptor = .monthlyByDay(interval: nextInterval, days: days.isEmpty ? [selectedMonthDay] : days)
    case .monthlyByWeekday(_, let weekdays):
      descriptor = .monthlyByWeekday(
        interval: nextInterval,
        weekdays: weekdays.isEmpty
          ? [ReminderRecurrenceWeekdayOrdinal(weekday: selectedWeekday, weekNumber: selectedWeekNumber)]
          : weekdays
      )
    case .yearly:
      descriptor = .yearly(interval: nextInterval)
    }
  }

  private func toggleWeekday(_ weekday: Int) {
    let current = Set(weeklyWeekdays)
    let next: [Int]
    if current.contains(weekday), current.count > 1 {
      next = current.filter { $0 != weekday }.sorted()
    } else {
      next = current.union([weekday]).sorted()
    }
    descriptor = .weekly(interval: interval(for: descriptor), weekdays: next)
  }

  private static let weekdayValues = [1, 2, 3, 4, 5, 6, 7]
  private static let monthOrdinals = [1, 2, 3, 4, 5, -1]

  private static func weekdayTitle(_ weekday: Int) -> String {
    switch weekday {
    case 1: "일"
    case 2: "월"
    case 3: "화"
    case 4: "수"
    case 5: "목"
    case 6: "금"
    case 7: "토"
    default: "?"
    }
  }

  private static func monthOrdinalTitle(_ ordinal: Int) -> String {
    switch ordinal {
    case -1: "마지막"
    case 1: "첫째"
    case 2: "둘째"
    case 3: "셋째"
    case 4: "넷째"
    case 5: "다섯째"
    default: "\(ordinal)"
    }
  }
}
