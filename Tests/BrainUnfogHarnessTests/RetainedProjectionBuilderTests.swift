import CryptoKit
import XCTest
@testable import BrainUnfogHarness

final class RetainedProjectionBuilderTests: XCTestCase {
  func testBuildPreservesManagedMetadataFromLoadedPageSnapshots() async throws {
    let graphRootURL = try makeGraphRoot(named: "RetainedProjectionGraph")
    let projectID = retainedProjectID(for: "reminder-list-1")
    let taskID = ReminderProjectionIdentity.taskID(for: "reminder-1")
    let store = LogseqProjectPageStore(
      pagesRootURL: graphRootURL.appendingPathComponent("pages", isDirectory: true)
    )

    _ = try await store.upsertPage(
      .init(
        projectID: projectID,
        title: "Launch Plan",
        reminderListExternalIdentifier: "reminder-list-1"
      ),
      noteMarkdown: "Retained seam note",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "Prepare launch",
          isCompleted: false,
          date: "2026-04-25 14:30",
          duration: "45",
          repeatRule: "weekly",
          reminderExternalIdentifier: "reminder-1",
          calendarEventExternalIdentifier: "event-1"
        )
      ]
    )

    let pages = try await store.loadProjectPagesInScope()
    let snapshot = try RetainedProjectionBuilder.build(
      .init(
        pages: pages,
        projectBindings: [
          .init(projectID: projectID, reminderListExternalIdentifier: "reminder-list-1")
        ],
        taskBindings: [
          .init(
            projectID: projectID,
            taskID: taskID,
            reminderExternalIdentifier: "reminder-1",
            calendarEventExternalIdentifier: "event-1"
          )
        ]
      )
    )

    let project = try XCTUnwrap(snapshot.projects.onlyValue)
    let task = try XCTUnwrap(project.tasks.onlyValue)

    XCTAssertEqual(project.identity.projectID, projectID)
    XCTAssertEqual(project.identity.reminderListExternalIdentifier, "reminder-list-1")
    XCTAssertEqual(project.title, "Launch Plan")
    XCTAssertTrue(project.noteMarkdown.contains("Retained seam note"))

    XCTAssertEqual(task.identity.taskID, taskID)
    XCTAssertEqual(task.identity.reminderExternalIdentifier, "reminder-1")
    XCTAssertEqual(task.identity.calendarEventExternalIdentifier, "event-1")
    XCTAssertEqual(task.title, "Prepare launch")
    XCTAssertEqual(task.schedule.rawDate, "2026-04-25 14:30")
    XCTAssertEqual(task.schedule.rawDuration, "45")
    XCTAssertEqual(task.schedule.rawRepeatRule, "weekly")
    XCTAssertEqual(task.schedule.canonicalRepeatRule, "weekly|1|")
    XCTAssertEqual(task.schedule.durationMinutes, 45)
    XCTAssertTrue(task.schedule.hasExplicitTime)
  }

  func testBuildIgnoresTaggedPagesWithoutManagedProjectIdentity() throws {
    let source = RetainedProjectionBuilder.Source(
      pages: [
        makePageSnapshot(
          title: "Claimable Project",
          projectID: nil,
          reminderListExternalIdentifier: nil,
          usesProjectTag: true
        )
      ]
    )

    let snapshot = try RetainedProjectionBuilder.build(source)

    XCTAssertTrue(snapshot.projects.isEmpty)
  }

  func testBuildDerivesRuntimeIdentitiesFromReminderIdentifiers() throws {
    let snapshot = try RetainedProjectionBuilder.build(
      .init(
        pages: [
          makePageSnapshot(
            title: "Reminder Project",
            projectID: nil,
            reminderListExternalIdentifier: "reminder-list-1",
            usesProjectTag: false,
            managedTasks: [
              .init(
                title: "Reminder task",
                isCompleted: false,
                reminderExternalIdentifier: "reminder-1"
              )
            ]
          )
        ]
      )
    )

    let project = try XCTUnwrap(snapshot.projects.onlyValue)
    let task = try XCTUnwrap(project.tasks.onlyValue)

    XCTAssertEqual(
      project.identity.projectID,
      RetainedProjectionBuilder.derivedProjectID(for: "reminder-list-1")
    )
    XCTAssertEqual(project.identity.reminderListExternalIdentifier, "reminder-list-1")
    XCTAssertEqual(task.identity.taskID, ReminderProjectionIdentity.taskID(for: "reminder-1"))
    XCTAssertEqual(task.identity.reminderExternalIdentifier, "reminder-1")
  }

  func testBuildFailsClosedOnDuplicateProjectIdentityValues() {
    let projectID = UUID()

    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [
            makePageSnapshot(title: "A", projectID: projectID, reminderListExternalIdentifier: nil),
            makePageSnapshot(title: "B", projectID: projectID, reminderListExternalIdentifier: nil),
          ]
        )
      )
    ) { error in
      XCTAssertEqual(error as? RetainedProjectionBuilder.Error, .duplicateProjectID(projectID))
    }

    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [],
          projectBindings: [
            .init(projectID: UUID(), reminderListExternalIdentifier: "reminder-list-1"),
            .init(projectID: UUID(), reminderListExternalIdentifier: "reminder-list-1"),
          ]
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? RetainedProjectionBuilder.Error,
        .duplicateReminderListExternalIdentifier("reminder-list-1")
      )
    }
  }

  func testBuildFailsClosedOnDuplicateTaskIdentityValues() {
    let sharedTaskID = UUID()

    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [
            makePageSnapshot(
              title: "Project",
              projectID: UUID(),
              reminderListExternalIdentifier: nil,
              managedTasks: [
                .init(taskID: sharedTaskID, title: "A", isCompleted: false),
                .init(taskID: sharedTaskID, title: "B", isCompleted: false),
              ]
            )
          ]
        )
      )
    ) { error in
      XCTAssertEqual(error as? RetainedProjectionBuilder.Error, .duplicateTaskID(sharedTaskID))
    }

    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [
            makePageSnapshot(
              title: "Project",
              projectID: UUID(),
              reminderListExternalIdentifier: nil,
              managedTasks: [
                .init(
                  title: "A",
                  isCompleted: false,
                  reminderExternalIdentifier: "reminder-1"
                ),
                .init(
                  title: "B",
                  isCompleted: false,
                  reminderExternalIdentifier: "reminder-1"
                ),
              ]
            )
          ]
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? RetainedProjectionBuilder.Error,
        .duplicateReminderExternalIdentifier("reminder-1")
      )
    }

    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [
            makePageSnapshot(
              title: "Project",
              projectID: UUID(),
              reminderListExternalIdentifier: nil,
              managedTasks: [
                .init(
                  taskID: UUID(),
                  title: "A",
                  isCompleted: false,
                  calendarEventExternalIdentifier: "event-1"
                ),
                .init(
                  taskID: UUID(),
                  title: "B",
                  isCompleted: false,
                  calendarEventExternalIdentifier: "event-1"
                ),
              ]
            )
          ]
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? RetainedProjectionBuilder.Error,
        .duplicateCalendarEventExternalIdentifier("event-1")
      )
    }
  }

  func testBuildFailsClosedOnConflictingProjectIdentity() {
    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [
            makePageSnapshot(
              title: "Conflicting Project",
              projectID: UUID(),
              reminderListExternalIdentifier: "reminder-list-1"
            )
          ]
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? RetainedProjectionBuilder.Error,
        .conflictingProjectIdentity(pageTitle: "Conflicting Project")
      )
    }
  }

  func testBuildFailsClosedOnConflictingTaskIdentity() {
    let legacyTaskID = UUID()

    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [
            makePageSnapshot(
              title: "Conflicting Project",
              projectID: UUID(),
              reminderListExternalIdentifier: nil,
              managedTasks: [
                .init(
                  taskID: legacyTaskID,
                  title: "Conflicting Task",
                  isCompleted: false,
                  reminderExternalIdentifier: "reminder-1"
                )
              ]
            )
          ]
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? RetainedProjectionBuilder.Error,
        .damagedTaskIdentity(
          projectTitle: "Conflicting Project",
          taskTitle: "Conflicting Task"
        )
      )
    }
  }

  func testBuildFailsClosedOnMissingPageAndOrphanBindings() {
    let projectID = retainedProjectID(for: "reminder-list-1")
    let taskID = UUID()

    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [],
          projectBindings: [
            .init(projectID: projectID, reminderListExternalIdentifier: "reminder-list-1")
          ]
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? RetainedProjectionBuilder.Error,
        .missingPageForProjectBinding(
          projectID: projectID,
          reminderListExternalIdentifier: "reminder-list-1"
        )
      )
    }

    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [
            makePageSnapshot(
              title: "Bound Project",
              projectID: projectID,
              reminderListExternalIdentifier: "reminder-list-1",
              managedTasks: [.init(taskID: taskID, title: "Safe task", isCompleted: false)]
            )
          ],
          taskBindings: [
            .init(
              projectID: projectID,
              taskID: UUID(),
              reminderExternalIdentifier: "reminder-1",
              calendarEventExternalIdentifier: nil
            )
          ]
        )
      )
    ) { error in
      guard case .orphanTaskBinding = error as? RetainedProjectionBuilder.Error else {
        return XCTFail("Expected orphanTaskBinding, got \(error)")
      }
    }
  }

  func testBuildFailsClosedOnDamagedTaskIdentityAndMissingPageShape() {
    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [
            makePageSnapshot(
              title: "Damaged Project",
              projectID: UUID(),
              reminderListExternalIdentifier: nil,
              managedTasks: [
                .init(
                  title: "Damaged task",
                  isCompleted: false,
                  calendarEventExternalIdentifier: "event-1"
                )
              ]
            )
          ]
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? RetainedProjectionBuilder.Error,
        .damagedTaskIdentity(projectTitle: "Damaged Project", taskTitle: "Damaged task")
      )
    }

    XCTAssertThrowsError(
      try RetainedProjectionBuilder.build(
        .init(
          pages: [
            makePageSnapshot(
              title: "Projectless Page",
              projectID: nil,
              reminderListExternalIdentifier: nil,
              externalTasks: [
                .init(taskID: UUID(), title: "Stale task", isCompleted: false)
              ]
            )
          ]
        )
      )
    ) { error in
      XCTAssertEqual(
        error as? RetainedProjectionBuilder.Error,
        .damagedTaskIdentity(projectTitle: "Projectless Page", taskTitle: "Stale task")
      )
    }

  }

  private func makeGraphRoot(
    named name: String,
    config: String = ""
  ) throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
      .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    if !config.isEmpty {
      try config.write(
        to: rootURL.appendingPathComponent("config.edn", isDirectory: false),
        atomically: true,
        encoding: .utf8
      )
    }
    return rootURL
  }

  private func makePageSnapshot(
    title: String,
    projectID: UUID?,
    reminderListExternalIdentifier: String?,
    usesProjectTag: Bool = true,
    managedTasks: [LogseqProjectPageStore.TaskRecord] = [],
    externalTasks: [LogseqProjectPageStore.TaskRecord] = []
  ) -> LogseqProjectPageStore.PageSnapshot {
    LogseqProjectPageStore.PageSnapshot(
      fileURL: URL(fileURLWithPath: "/tmp/\(title).md"),
      title: title,
      projectID: projectID,
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      usesProjectTag: usesProjectTag,
      isBUFOwned: projectID != nil,
      hasManagedTaskSection: true,
      noteMarkdown: "",
      managedTasks: managedTasks,
      externalTasks: externalTasks,
      canSafelyPersistProjectNote: true
    )
  }

  private func retainedProjectID(for reminderListExternalIdentifier: String) -> UUID {
    let digest = SHA256.hash(data: Data("reminder-project|\(reminderListExternalIdentifier)".utf8))
    var bytes = Array(digest.prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}

private extension Array {
  var onlyValue: Element? {
    count == 1 ? self[0] : nil
  }
}
