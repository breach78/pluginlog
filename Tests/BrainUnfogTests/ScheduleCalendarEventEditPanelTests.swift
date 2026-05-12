import XCTest
@testable import BrainUnfog

final class ScheduleCalendarEventEditPanelTests: XCTestCase {
  func testEventNoteEditorUsesSharedLinkedEditorBehavior() throws {
    let scheduleSource = try scheduleCalendarEventEditPanelSource()
    let taskEditorSource = try timelineTaskEditPopoverSource()

    XCTAssertTrue(scheduleSource.contains("TaskEditNoteEditor("))
    XCTAssertTrue(scheduleSource.contains("measuredHeight: $noteHeight"))
    XCTAssertTrue(scheduleSource.contains("isEditable: event.canEditTiming"))
    XCTAssertFalse(scheduleSource.contains("ScheduleUITokens.Panel.noteFontSize"))
    XCTAssertFalse(scheduleSource.contains("ScheduleUITokens.Panel.noteMinHeight"))
    XCTAssertFalse(scheduleSource.contains("TextEditor(text: $noteText)"))

    XCTAssertTrue(taskEditorSource.contains("struct TaskEditNoteEditor: View"))
    XCTAssertTrue(taskEditorSource.contains("LinkedTextEditor("))
    XCTAssertTrue(taskEditorSource.contains("font: TaskEditTypography.noteNSFont"))
    XCTAssertTrue(taskEditorSource.contains("TaskEditTypography.noteMinimumHeight"))
    XCTAssertTrue(taskEditorSource.contains("markdownPresentationMode: .livePreview"))
    XCTAssertTrue(taskEditorSource.contains(".taskEditFieldBackground(cornerRadius: 4)"))
  }

  @MainActor
  func testAllDayMultiDayEventUsesVisibleEndDayInEditFields() throws {
    let calendar = Calendar.autoupdatingCurrent
    let startDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 2))
    )
    let exclusiveEndDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 5))
    )

    let fields = ScheduleCalendarEventEditPanelContent.editFields(
      for: makeEvent(startDate: startDate, endDate: exclusiveEndDate, isAllDay: true)
    )

    XCTAssertEqual(fields.day, calendar.startOfDay(for: startDate))
    XCTAssertEqual(
      fields.endDay,
      try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
    )
    XCTAssertTrue(fields.isAllDay)
  }

  @MainActor
  func testTimedMultiDayEventKeepsEndDayAndEndTimeInEditFields() throws {
    let calendar = Calendar.autoupdatingCurrent
    let startDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 22, minute: 30))
    )
    let endDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 0, minute: 15))
    )

    let fields = ScheduleCalendarEventEditPanelContent.editFields(
      for: makeEvent(startDate: startDate, endDate: endDate, isAllDay: false)
    )

    XCTAssertEqual(fields.day, calendar.startOfDay(for: startDate))
    XCTAssertEqual(fields.endDay, calendar.startOfDay(for: endDate))
    XCTAssertFalse(fields.isAllDay)
    XCTAssertEqual(fields.startMinutes, 22 * 60 + 30)
    XCTAssertEqual(fields.endMinutes, 15)
  }

  func testCalendarEventDetectsMultiDaySpans() throws {
    let calendar = Calendar.autoupdatingCurrent
    let startDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 9))
    )
    let endDate = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 9))
    )

    XCTAssertTrue(makeEvent(startDate: startDate, endDate: endDate, isAllDay: false).spansMultipleDays)
  }

  private func makeEvent(
    startDate: Date,
    endDate: Date,
    isAllDay: Bool
  ) -> ScheduleCalendarEvent {
    ScheduleCalendarEvent(
      id: UUID().uuidString,
      eventIdentifier: "event-id",
      externalIdentifier: "external-id",
      occurrenceDate: nil,
      calendarIdentifier: "calendar-id",
      calendarTitle: "Calendar",
      calendarColorHex: nil,
      title: "Event",
      notes: "Notes",
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      isRecurring: false,
      isDetached: false,
      canEditTiming: true,
      editTimingRestrictionReason: nil
    )
  }

  private func scheduleCalendarEventEditPanelSource() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = root.appendingPathComponent(
      "import/BUF/Features/Schedule/ScheduleCalendarEventEditPanel.swift"
    )
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func timelineTaskEditPopoverSource() throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = root.appendingPathComponent(
      "import/BUF/Features/Timeline/TimelineTaskEditPopover.swift"
    )
    return try String(contentsOf: url, encoding: .utf8)
  }
}
