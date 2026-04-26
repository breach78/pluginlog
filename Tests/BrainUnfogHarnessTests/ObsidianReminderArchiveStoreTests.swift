import XCTest
@testable import BrainUnfogHarness

final class ObsidianReminderArchiveStoreTests: XCTestCase {
  func testSavesLoadsAndRemovesArchiveSnapshotInVaultSidecar() throws {
    let vaultURL = try makeVault()
    let store = ObsidianReminderArchiveStore(vaultRootURL: vaultURL)
    let archivedAt = Date(timeIntervalSince1970: 1_800)
    let snapshot = ObsidianReminderArchiveSnapshot(
      archivedAt: archivedAt,
      sourceVaultRelativePath: "raw/projects/Project.md",
      listDetail: ReminderArchiveListDetailSnapshot(
        identifier: "list-1",
        externalIdentifier: "list-1",
        title: "Project",
        colorHex: "#ff0000",
        calendarTypeRaw: 1,
        sourceIdentifier: "source-1",
        sourceTitle: "iCloud",
        sourceTypeRaw: 2
      ),
      list: ReminderListImportSnapshot(
        identifier: "list-1",
        externalIdentifier: "list-1",
        title: "Project",
        colorHex: "#ff0000"
      ),
      items: [
        ReminderItemImportSnapshot(
          identifier: "task-1",
          externalIdentifier: "task-1",
          parentExternalIdentifier: nil,
          sourceListIdentifier: "list-1",
          sourceListTitle: "Project",
          title: "Task",
          notes: "note",
          attachmentCount: 0,
          isCompleted: false,
          completionDate: nil,
          startDate: nil,
          dueDate: Date(timeIntervalSince1970: 2_000),
          scheduleHasExplicitTime: true,
          scheduledDurationMinutes: nil,
          priority: 5,
          recurrenceRuleRaw: "daily|110",
          isFlagged: false,
          requiredWorkDays: 0,
          createdAt: Date(timeIntervalSince1970: 1_000),
          modifiedAt: Date(timeIntervalSince1970: 1_500)
        )
      ],
      taskDetails: [
        ReminderArchiveTaskDetailSnapshot(
          identifier: "task-1",
          externalIdentifier: "task-1",
          calendarIdentifier: "list-1",
          title: "Task",
          location: "Desk",
          notes: "note",
          urlString: "https://example.com",
          creationDate: Date(timeIntervalSince1970: 900),
          lastModifiedDate: Date(timeIntervalSince1970: 1_500),
          timeZoneIdentifier: "Asia/Seoul",
          startDateComponents: ReminderArchiveDateComponentsSnapshot(
            calendarIdentifier: "gregorian",
            timeZoneIdentifier: "Asia/Seoul",
            year: 2026,
            month: 4,
            day: 25,
            hour: 8,
            minute: 30
          ),
          dueDateComponents: ReminderArchiveDateComponentsSnapshot(
            calendarIdentifier: "gregorian",
            timeZoneIdentifier: "Asia/Seoul",
            year: 2026,
            month: 4,
            day: 25,
            hour: 9,
            minute: 0
          ),
          isCompleted: false,
          completionDate: nil,
          priority: 5,
          recurrenceRules: [
            ReminderArchiveRecurrenceRuleSnapshot(
              frequencyRaw: 0,
              interval: 110,
              firstDayOfTheWeek: 0,
              recurrenceEnd: nil,
              daysOfTheWeek: [],
              daysOfTheMonth: [],
              monthsOfTheYear: [],
              weeksOfTheYear: [],
              daysOfTheYear: [],
              setPositions: []
            )
          ],
          alarms: [
            ReminderArchiveAlarmSnapshot(
              relativeOffset: -900,
              absoluteDate: nil,
              structuredLocation: ReminderArchiveStructuredLocationSnapshot(
                title: "Office",
                latitude: 37.0,
                longitude: 127.0,
                radius: 100
              ),
              proximityRaw: 1,
              typeRaw: 0,
              emailAddress: nil,
              soundName: "Ping",
              urlString: nil
            )
          ]
        )
      ]
    )

    try store.save(snapshot, forListIdentifier: "list-1")

    XCTAssertEqual(try store.load(forListIdentifier: "list-1"), snapshot)
    XCTAssertTrue(FileManager.default.fileExists(atPath: store.archiveRootURL.path))

    try store.remove(forListIdentifier: "list-1")

    XCTAssertNil(try store.load(forListIdentifier: "list-1"))
  }

  private func makeVault() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ObsidianReminderArchiveStore-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
