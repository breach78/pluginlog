import XCTest
@testable import BrainUnfogHarness

@MainActor
final class ObsidianRetainedTaskCommandServiceTests: XCTestCase {
  private var temporaryRoots: [URL] = []

  override func setUp() async throws {
    try await super.setUp()
    ReminderSyncBaselineStore.reset()
  }

  override func tearDown() async throws {
    ReminderSyncBaselineStore.reset()
    for root in temporaryRoots {
      try? FileManager.default.removeItem(at: root)
    }
    temporaryRoots = []
    try await super.tearDown()
  }

  func testCompletionWritesObsidianTaskAndReminderWithoutCalendarWrite() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianCommandData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      body: projectNote(
        body: """
        - [ ] Task one
          %% brain-unfog: {"reminder_external_id":"task-1"} %%
        """
      )
    )
    let provider = FakeObsidianCommandReminderProjectProvider()
    provider.snapshots["task-1"] = remoteSnapshot(title: "Task one")
    upsertBaseline(title: "Task one", isCompleted: false, date: nil)

    let result = try await ObsidianRetainedTaskCommandService.setTaskCompletion(
      vaultRootURL: vault,
      projectID: projectID,
      taskID: taskID,
      isCompleted: true,
      completionDate: fixedNow,
      reminderProjectProvider: provider
    )

    let raw = try await firstRawMarkdown(in: vault)
    XCTAssertTrue(raw.contains("- [x] Task one"))
    XCTAssertEqual(provider.completionWrites.map(\.isCompleted), [true])
    XCTAssertEqual(result.calendarBridgeDecision, .noAction)
    XCTAssertNil(result.calendarWriteMarker)
    XCTAssertEqual(ReminderSyncBaselineStore.baseline(for: "task-1")?.state.isCompleted, true)
  }

  func testScheduleWritesObsidianMetadataAndReminderDueDate() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianCommandData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      body: projectNote(
        body: """
        - [ ] Task one
          %% brain-unfog: {"reminder_external_id":"task-1"} %%
        """
      )
    )
    let provider = FakeObsidianCommandReminderProjectProvider()
    provider.snapshots["task-1"] = remoteSnapshot(title: "Task one")
    upsertBaseline(title: "Task one", isCompleted: false, date: nil)
    let day = makeDate(year: 2026, month: 4, day: 25)

    _ = try await ObsidianRetainedTaskCommandService.setTaskSchedule(
      vaultRootURL: vault,
      projectID: projectID,
      taskID: taskID,
      day: day,
      timeMinutes: 9 * 60 + 30,
      durationMinutes: 45,
      calendar: calendar,
      reminderProjectProvider: provider
    )

    let raw = try await firstRawMarkdown(in: vault)
    XCTAssertTrue(raw.contains(#""date":"2026-04-25","time":"09:30","duration":45"#))
    XCTAssertEqual(provider.scheduleWrites.count, 1)
    XCTAssertEqual(provider.scheduleWrites.first?.hasExplicitTime, true)
    XCTAssertEqual(provider.scheduleWrites.first?.dueDate.map(dateTimeString), "2026-04-25 09:30")
    XCTAssertEqual(ReminderSyncBaselineStore.baseline(for: "task-1")?.state.date, "2026-04-25 09:30")
  }

  func testDurationOnlyEditDoesNotWriteReminderSchedule() async throws {
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      body: projectNote(
        body: """
        - [ ] Task one
          %% brain-unfog: {"reminder_external_id":"task-1","date":"2026-04-25","time":"09:30","duration":30} %%
        """
      )
    )
    let provider = FakeObsidianCommandReminderProjectProvider()
    let day = makeDate(year: 2026, month: 4, day: 25)

    _ = try await ObsidianRetainedTaskCommandService.setTaskSchedule(
      vaultRootURL: vault,
      projectID: projectID,
      taskID: taskID,
      day: day,
      timeMinutes: 9 * 60 + 30,
      durationMinutes: 60,
      calendar: calendar,
      reminderProjectProvider: provider
    )

    let raw = try await firstRawMarkdown(in: vault)
    XCTAssertTrue(raw.contains(#""duration":60"#))
    XCTAssertTrue(provider.scheduleWrites.isEmpty)
    XCTAssertNil(ReminderSyncBaselineStore.baseline(for: "task-1"))
  }

  func testReminderFailureRollsBackObsidianWrite() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianCommandData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      body: projectNote(
        body: """
        - [ ] Task one
          %% brain-unfog: {"reminder_external_id":"task-1","date":"2026-04-25"} %%
        """
      )
    )
    let provider = FakeObsidianCommandReminderProjectProvider()
    provider.snapshots["task-1"] = remoteSnapshot(title: "Task one", date: "2026-04-25")
    upsertBaseline(title: "Task one", isCompleted: false, date: "2026-04-25")
    provider.scheduleError = FakeObsidianCommandReminderError.requestedFailure

    do {
      _ = try await ObsidianRetainedTaskCommandService.setTaskSchedule(
        vaultRootURL: vault,
        projectID: projectID,
        taskID: taskID,
        day: makeDate(year: 2026, month: 4, day: 26),
        timeMinutes: nil,
        durationMinutes: nil,
        calendar: calendar,
        reminderProjectProvider: provider
      )
      XCTFail("Expected schedule failure")
    } catch FakeObsidianCommandReminderError.requestedFailure {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let raw = try await firstRawMarkdown(in: vault)
    XCTAssertTrue(raw.contains(#""date":"2026-04-25""#))
    XCTAssertFalse(raw.contains(#""date":"2026-04-26""#))
  }

  func testDuplicateTaskIDsFailBeforeMarkdownOrReminderWrite() async throws {
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      body: projectNote(
        body: """
        - [ ] One
          %% brain-unfog: {"reminder_external_id":"task-1"} %%
        - [ ] Two
          %% brain-unfog: {"reminder_external_id":"task-1"} %%
        """
      )
    )
    let provider = FakeObsidianCommandReminderProjectProvider()

    do {
      _ = try await ObsidianRetainedTaskCommandService.setTaskCompletion(
        vaultRootURL: vault,
        projectID: projectID,
        taskID: taskID,
        isCompleted: true,
        completionDate: fixedNow,
        reminderProjectProvider: provider
      )
      XCTFail("Expected duplicate identity failure")
    } catch RetainedTaskCommandError.retainedProjectionFailed {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let raw = try await firstRawMarkdown(in: vault)
    XCTAssertTrue(raw.contains("- [ ] One"))
    XCTAssertTrue(raw.contains("- [ ] Two"))
    XCTAssertTrue(provider.completionWrites.isEmpty)
  }

  func testRemoteReminderEditAfterBaselineBlocksCompletionBeforeMarkdownWrite() async throws {
    let dataRoot = try makeTemporaryDirectory(prefix: "ObsidianCommandData")
    ReminderSyncBaselineStore.install(dataDirectory: dataRoot)
    let vault = try makeTemporaryVault()
    _ = try writeProjectNote(
      vault: vault,
      body: projectNote(
        body: """
        - [ ] Task one
          %% brain-unfog: {"reminder_external_id":"task-1"} %%
        """
      )
    )
    let provider = FakeObsidianCommandReminderProjectProvider()
    provider.snapshots["task-1"] = remoteSnapshot(
      title: "Task one",
      isCompleted: true,
      modifiedAt: Date(timeIntervalSince1970: 4_000)
    )
    upsertBaseline(title: "Task one", isCompleted: false, date: nil)

    do {
      _ = try await ObsidianRetainedTaskCommandService.setTaskCompletion(
        vaultRootURL: vault,
        projectID: projectID,
        taskID: taskID,
        isCompleted: true,
        completionDate: fixedNow,
        reminderProjectProvider: provider
      )
      XCTFail("Expected stale reminder baseline failure")
    } catch RetainedTaskCommandError.retainedProjectionFailed {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let raw = try await firstRawMarkdown(in: vault)
    XCTAssertTrue(raw.contains("- [ ] Task one"))
    XCTAssertTrue(provider.completionWrites.isEmpty)
  }

  private var projectID: UUID {
    RetainedProjectionBuilder.derivedProjectID(for: "list-1")
  }

  private var taskID: UUID {
    ReminderProjectionIdentity.taskID(for: "task-1")
  }

  private var fixedNow: Date { Date(timeIntervalSince1970: 2_000) }
  private var fixedRemoteDate: Date { Date(timeIntervalSince1970: 1_000) }

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    return calendar
  }

  private func projectNote(body: String) -> String {
    """
    ---
    tags:
      - 프로젝트
    reminder_list_external_id: list-1
    ---
    \(body)
    """
  }

  private func firstRawMarkdown(in vault: URL) async throws -> String {
    let snapshots = try await ObsidianProjectMarkdownStore(vaultRootURL: vault)
      .loadProjectNotesInScope()
    return try XCTUnwrap(snapshots.first?.rawMarkdown)
  }

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    return components.date!
  }

  private func dateTimeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
  }

  private func upsertBaseline(
    title: String,
    isCompleted: Bool,
    date: String?
  ) {
    ReminderSyncBaselineStore.upsert(
      reminderExternalIdentifier: "task-1",
      state: ReminderSyncTaskState(
        title: title,
        isCompleted: isCompleted,
        date: date,
        repeatRule: nil,
        noteText: nil
      ),
      remoteModifiedAt: fixedRemoteDate,
      now: fixedNow
    )
  }

  private func remoteSnapshot(
    title: String,
    isCompleted: Bool = false,
    date: String? = nil,
    modifiedAt: Date? = nil
  ) -> ReminderTaskRemoteSnapshot {
    let dueDate: Date?
    let hasExplicitTime: Bool
    if let date, date.count > 10 {
      dueDate = dateTimeFormatter.date(from: date)
      hasExplicitTime = true
    } else if let date {
      dueDate = dayFormatter.date(from: date)
      hasExplicitTime = false
    } else {
      dueDate = nil
      hasExplicitTime = false
    }
    return ReminderTaskRemoteSnapshot(
      identifier: "task-1",
      externalIdentifier: "task-1",
      calendarIdentifier: "list-1",
      title: title,
      noteText: "",
      isCompleted: isCompleted,
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      priority: 0,
      modifiedAt: modifiedAt ?? fixedRemoteDate
    )
  }

  private var dayFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }

  private var dateTimeFormatter: DateFormatter {
    let formatter = dayFormatter
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
  }

  private func makeTemporaryVault() throws -> URL {
    try makeTemporaryDirectory(prefix: "ObsidianCommandVault")
  }

  private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    temporaryRoots.append(root)
    return root
  }

  @discardableResult
  private func writeProjectNote(vault: URL, body: String) throws -> URL {
    let projects = vault
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    let url = projects.appendingPathComponent("Project.md", isDirectory: false)
    try body.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}

private enum FakeObsidianCommandReminderError: Error {
  case requestedFailure
}

@MainActor
private final class FakeObsidianCommandReminderProjectProvider: ReminderProjectProvider {
  struct CompletionWrite: Equatable {
    var isCompleted: Bool
    var completionDate: Date?
  }

  struct ScheduleWrite: Equatable {
    var dueDate: Date?
    var hasExplicitTime: Bool
  }

  var completionWrites: [CompletionWrite] = []
  var scheduleWrites: [ScheduleWrite] = []
  var snapshots: [String: ReminderTaskRemoteSnapshot] = [:]
  var completionError: Error?
  var scheduleError: Error?

  var reminderGateway: ReminderGateway? { nil }
  var defaultCalendarIdentifierForNewReminders: String? { nil }

  func requestAccess() async throws -> Bool { true }

  func setTaskCompletion(
    for task: ReminderTaskReference,
    isCompleted: Bool,
    completionDate: Date?
  ) throws -> ReminderTaskRemoteMetadata? {
    completionWrites.append(
      CompletionWrite(isCompleted: isCompleted, completionDate: completionDate)
    )
    if let completionError { throw completionError }
    return metadata(for: task)
  }

  func setTaskSchedule(
    for task: ReminderTaskReference,
    dueDate: Date?,
    hasExplicitTime: Bool
  ) throws -> ReminderTaskRemoteMetadata? {
    scheduleWrites.append(ScheduleWrite(dueDate: dueDate, hasExplicitTime: hasExplicitTime))
    if let scheduleError { throw scheduleError }
    return metadata(for: task)
  }

  func createProjectList(title: String) throws -> ReminderProjectListSnapshot {
    ReminderProjectListSnapshot(identifier: "list-1", externalIdentifier: "list-1", title: title, colorHex: nil)
  }
  func removeProjectList(identifier: String) throws {}
  func setProjectTitle(identifier: String, title: String) throws -> ReminderProjectListSnapshot? { nil }
  func setProjectColor(identifier: String, colorHex: String?) throws -> ReminderProjectListSnapshot? { nil }
  func createTaskReminder(inProject identifier: String, title: String, dueDate: Date?, hasExplicitTime: Bool, noteText: String) throws -> ReminderTaskRemoteMetadata? { nil }
  func removeTaskReminder(for task: ReminderTaskReference) throws -> Bool { false }
  func taskSnapshot(for task: ReminderTaskReference) throws -> ReminderTaskRemoteSnapshot? {
    guard let identifier = task.reminderExternalIdentifier else { return nil }
    return snapshots[identifier]
  }
  func setTaskTitle(for task: ReminderTaskReference, title: String) throws -> ReminderTaskRemoteMetadata? { nil }
  func setTaskReminderNote(for task: ReminderTaskReference, noteText: String) throws -> ReminderTaskRemoteMetadata? { nil }
  func setTaskRecurrence(for task: ReminderTaskReference, recurrenceRuleRaw: String?) throws -> ReminderTaskRemoteMetadata? { nil }
  func setTaskPresentation(for task: ReminderTaskReference, priority: Int) throws -> ReminderTaskRemoteMetadata? { nil }
  func moveTaskReminder(for task: ReminderTaskReference, toProject identifier: String) throws -> ReminderTaskRemoteMetadata? { nil }
  func restoreArchivedProject(_ project: ReminderArchivedProjectSnapshot) throws -> ReminderProjectRestoreResult {
    throw NSError(domain: "unused", code: 1)
  }
  func removeArchivedProjectLists(_ projects: [ReminderProjectListReference]) -> ReminderProjectCleanupResult {
    ReminderProjectCleanupResult(removedCount: 0, failedProjectIDs: [])
  }

  private func metadata(for task: ReminderTaskReference) -> ReminderTaskRemoteMetadata {
    ReminderTaskRemoteMetadata(
      identifier: task.reminderIdentifier ?? "task-1",
      externalIdentifier: task.reminderExternalIdentifier,
      modifiedAt: Date(timeIntervalSince1970: 3_000)
    )
  }
}
