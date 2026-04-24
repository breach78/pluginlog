import XCTest
@testable import BrainUnfogHarness

final class LogseqProjectPageStoreTests: XCTestCase {
  func testRoundTripManagedSectionPreservesNonManagedContent() async throws {
    let graphRootURL = try makeGraphRoot(
      named: "TripleLowbarGraph",
      config: ":file/name-format :triple-lowbar"
    )
    let store = LogseqProjectPageStore(
      pagesRootURL: graphRootURL.appendingPathComponent("pages", isDirectory: true)
    )
    let projectID = UUID()
    let taskID = UUID()

    let disposition = try await store.upsertPage(
      .init(
        projectID: projectID,
        title: "Alpha/Beta",
        reminderListExternalIdentifier: "reminder-list-1"
      ),
      noteMarkdown: "Intro line\n- plain bullet\n  continuation",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "Prepare launch",
          isCompleted: false,
          date: "2026-04-25 14:00",
          duration: "45",
          repeatRule: "weekly",
          reminderExternalIdentifier: "reminder-1",
          calendarEventExternalIdentifier: "event-1"
        )
      ]
    )

    XCTAssertEqual(disposition, .created)

    let expectedFileURL = graphRootURL
      .appendingPathComponent("pages", isDirectory: true)
      .appendingPathComponent("Alpha___Beta.md", isDirectory: false)
    XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFileURL.path))

    let fileContents = try String(contentsOf: expectedFileURL, encoding: .utf8)
    XCTAssertTrue(fileContents.contains("tags:: 프로젝트"))
    XCTAssertFalse(fileContents.contains("brain_unfog_project_id::"))
    XCTAssertFalse(fileContents.contains("## Brain Unfog Managed Tasks"))
    XCTAssertFalse(fileContents.contains("<!-- generated-by: Brain Unfog -->"))

    let loaded = try await store.loadProjectPage(
      for: .init(
        projectID: projectID,
        title: "Alpha/Beta",
        reminderListExternalIdentifier: "reminder-list-1"
      )
    )

    XCTAssertEqual(loaded?.fileURL.standardizedFileURL, expectedFileURL.standardizedFileURL)
    XCTAssertEqual(loaded?.title, "Alpha/Beta")
    XCTAssertEqual(loaded?.reminderListExternalIdentifier, "reminder-list-1")
    XCTAssertTrue(loaded?.noteMarkdown.contains("Intro line\n- plain bullet\n  continuation") == true)
    XCTAssertEqual(loaded?.managedTasks, [])
    XCTAssertEqual(
      loaded?.externalTasks,
      [
        .init(
          taskID: taskID,
          title: "Prepare launch",
          isCompleted: false,
          date: "2026-04-25 14:00",
          duration: "45",
          repeatRule: "weekly",
          reminderExternalIdentifier: "reminder-1",
          calendarEventExternalIdentifier: "event-1"
        )
      ]
    )
    XCTAssertEqual(loaded?.hasManagedTaskSection, false)
    XCTAssertEqual(loaded?.canSafelyPersistProjectNote, false)
  }

  func testUpsertRemovesLegacyProjectIdentityProperty() async throws {
    let graphRootURL = try makeGraphRoot(named: "RemoveLegacyProjectIdentityGraph")
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRootURL, withIntermediateDirectories: true)
    let projectID = UUID()
    let pageURL = pagesRootURL.appendingPathComponent("Legacy.md", isDirectory: false)
    try """
    tags:: 프로젝트
    brain_unfog_project_id:: \(projectID.uuidString.lowercased())
    reminder_list_external_id:: reminder-list-1

    Legacy note

    ## Brain Unfog Managed Tasks
    <!-- generated-by: Brain Unfog -->
    """.write(to: pageURL, atomically: true, encoding: .utf8)
    let store = LogseqProjectPageStore(pagesRootURL: pagesRootURL)

    _ = try await store.upsertPage(
      .init(
        projectID: projectID,
        title: "Legacy",
        reminderListExternalIdentifier: "reminder-list-1"
      ),
      noteMarkdown: "Updated note",
      managedTasks: []
    )

    let fileContents = try String(contentsOf: pageURL, encoding: .utf8)
    XCTAssertFalse(fileContents.contains("brain_unfog_project_id::"))
    XCTAssertFalse(fileContents.contains("## Brain Unfog Managed Tasks"))
    XCTAssertTrue(fileContents.contains("reminder_list_external_id:: reminder-list-1"))
    XCTAssertTrue(fileContents.contains("Updated note"))
  }

  func testUpsertWithoutReminderListDoesNotWriteLegacyProjectIdentityProperty() async throws {
    let graphRootURL = try makeGraphRoot(named: "NoLegacyProjectIdentityGraph")
    let store = LogseqProjectPageStore(
      pagesRootURL: graphRootURL.appendingPathComponent("pages", isDirectory: true)
    )

    _ = try await store.upsertPage(
      .init(
        projectID: UUID(),
        title: "Local Project",
        reminderListExternalIdentifier: nil
      ),
      noteMarkdown: "Local note",
      managedTasks: []
    )

    let pageURL = graphRootURL.appendingPathComponent("pages/Local Project.md", isDirectory: false)
    let fileContents = try String(contentsOf: pageURL, encoding: .utf8)
    XCTAssertFalse(fileContents.contains("brain_unfog_project_id::"))
    XCTAssertTrue(fileContents.contains("tags:: 프로젝트"))
  }

  func testLoadsHyphenatedReminderPropertyAliases() async throws {
    let graphRootURL = try makeGraphRoot(named: "HyphenatedReminderPropertyGraph")
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRootURL, withIntermediateDirectories: true)
    let pageURL = pagesRootURL.appendingPathComponent("Aliases.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder-list-external-id:: list-ext-1

    - TODO Aliased task
      reminder-external-id:: task-ext-1
    """.write(to: pageURL, atomically: true, encoding: .utf8)
    let store = LogseqProjectPageStore(pagesRootURL: pagesRootURL)

    let pages = try await store.loadProjectPagesInScope()

    XCTAssertEqual(pages.count, 1)
    let page = try XCTUnwrap(pages.first)
    XCTAssertEqual(page.reminderListExternalIdentifier, "list-ext-1")
    XCTAssertEqual(page.externalTasks.count, 1)
    XCTAssertEqual(page.externalTasks.first?.reminderExternalIdentifier, "task-ext-1")
  }

  func testExistingManagedTasksOutsideManagedSectionStayReadableAndBlockRewrite() async throws {
    let graphRootURL = try makeGraphRoot(named: "ReadOnlyImportGraph")
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRootURL, withIntermediateDirectories: true)

    let projectID = UUID()
    let taskID = UUID()
    let pageURL = pagesRootURL.appendingPathComponent("Read Only Project.md", isDirectory: false)
    try """
    tags:: [[프로젝트]]
    brain_unfog_project_id:: \(projectID.uuidString.lowercased())
    reminder_list_external_id:: reminder-list-1

    Intro
    - TODO Imported task
      brain_unfog_task_id:: \(taskID.uuidString.lowercased())
      date:: 2026-04-25 14:00
      repeat:: weekly
    """.write(to: pageURL, atomically: true, encoding: .utf8)

    let store = LogseqProjectPageStore(pagesRootURL: pagesRootURL)
    let loaded = try await store.loadProjectPage(
      for: .init(
        projectID: projectID,
        title: "Read Only Project",
        reminderListExternalIdentifier: "reminder-list-1"
      )
    )

    XCTAssertEqual(loaded?.usesProjectTag, true)
    XCTAssertEqual(loaded?.hasManagedTaskSection, false)
    XCTAssertEqual(loaded?.managedTasks, [])
    XCTAssertEqual(loaded?.externalTasks.count, 1)
    XCTAssertEqual(loaded?.canSafelyPersistProjectNote, false)
    XCTAssertTrue(loaded?.noteMarkdown.contains("Imported task") == true)

    _ = try await store.upsertPage(
      .init(
        projectID: projectID,
        title: "Read Only Project",
        reminderListExternalIdentifier: "reminder-list-1"
      ),
      noteMarkdown: try XCTUnwrap(loaded).noteMarkdown,
      managedTasks: []
    )

    let rewritten = try String(contentsOf: pageURL, encoding: .utf8)
    XCTAssertFalse(rewritten.contains("## Brain Unfog Managed Tasks"))
    XCTAssertFalse(rewritten.contains("<!-- generated-by: Brain Unfog -->"))
    XCTAssertTrue(rewritten.contains("Imported task"))
  }

  func testForeignTitleMatchedPageIsNotRewritten() async throws {
    let graphRootURL = try makeGraphRoot(named: "ForeignTitleGraph")
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRootURL, withIntermediateDirectories: true)

    let foreignPageURL = pagesRootURL.appendingPathComponent("Shared Title.md", isDirectory: false)
    try """
    tags:: 프로젝트

    Existing foreign page
    """.write(to: foreignPageURL, atomically: true, encoding: .utf8)
    XCTAssertTrue(FileManager.default.fileExists(atPath: foreignPageURL.path))

    let store = LogseqProjectPageStore(pagesRootURL: pagesRootURL)
    do {
      _ = try await store.upsertPage(
        .init(
          projectID: UUID(),
          title: "Shared Title",
          reminderListExternalIdentifier: "reminder-list-1"
        ),
        noteMarkdown: "BUF-owned note",
        managedTasks: []
      )
      XCTFail("Expected write to be rejected for a title-matched page without BUF ownership metadata")
    } catch let error as LogseqProjectPageStore.StoreError {
      switch error {
      case .pageNotOwned:
        break
      default:
        XCTFail("Unexpected store error: \(error)")
      }
    }
  }

  func testLoadProjectPageIgnoresForeignTitleMatchedPage() async throws {
    let graphRootURL = try makeGraphRoot(named: "ForeignLoadGraph")
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRootURL, withIntermediateDirectories: true)

    let foreignPageURL = pagesRootURL.appendingPathComponent("Shared Title.md", isDirectory: false)
    try """
    tags:: 프로젝트

    Existing foreign page
    """.write(to: foreignPageURL, atomically: true, encoding: .utf8)

    let store = LogseqProjectPageStore(pagesRootURL: pagesRootURL)
    let loaded = try await store.loadProjectPage(
      for: .init(
        projectID: UUID(),
        title: "Shared Title",
        reminderListExternalIdentifier: "reminder-list-1"
      )
    )

    XCTAssertNil(loaded)

    let claimable = try await store.loadClaimableTaggedPage(
      for: .init(
        projectID: UUID(),
        title: "Shared Title",
        reminderListExternalIdentifier: "reminder-list-1"
      )
    )
    XCTAssertEqual(claimable?.fileURL.standardizedFileURL, foreignPageURL.standardizedFileURL)
    XCTAssertEqual(claimable?.projectID, nil)
  }

  func testLoadClaimableTaggedPageRejectsConflictingReminderListIdentity() async throws {
    let graphRootURL = try makeGraphRoot(named: "ConflictingClaimGraph")
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRootURL, withIntermediateDirectories: true)

    let foreignPageURL = pagesRootURL.appendingPathComponent("Shared Title.md", isDirectory: false)
    try """
    tags:: 프로젝트
    reminder_list_external_id:: reminder-list-2

    Existing foreign page
    """.write(to: foreignPageURL, atomically: true, encoding: .utf8)

    let store = LogseqProjectPageStore(pagesRootURL: pagesRootURL)
    let claimable = try await store.loadClaimableTaggedPage(
      for: .init(
        projectID: UUID(),
        title: "Shared Title",
        reminderListExternalIdentifier: "reminder-list-1"
      )
    )

    XCTAssertNil(claimable)
  }

  func testLoadProjectPageRejectsDuplicateOwnedIdentityMatches() async throws {
    let graphRootURL = try makeGraphRoot(named: "DuplicateOwnedGraph")
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRootURL, withIntermediateDirectories: true)

    let projectID = UUID()
    try """
    tags:: 프로젝트
    brain_unfog_project_id:: \(projectID.uuidString.lowercased())

    First page
    """.write(
      to: pagesRootURL.appendingPathComponent("First Title.md", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )
    try """
    tags:: 프로젝트
    brain_unfog_project_id:: \(projectID.uuidString.lowercased())

    Second page
    """.write(
      to: pagesRootURL.appendingPathComponent("Second Title.md", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )

    let store = LogseqProjectPageStore(pagesRootURL: pagesRootURL)
    let loaded = try await store.loadProjectPage(
      for: .init(
        projectID: projectID,
        title: "First Title",
        reminderListExternalIdentifier: nil
      )
    )

    XCTAssertNil(loaded)
  }

  func testFilenameCodecReadsLegacyFormatFromConfig() throws {
    let graphRootURL = try makeGraphRoot(
      named: "LegacyFormatGraph",
      config: ":file/name-format :legacy"
    )

    let codec = LogseqPageFilenameCodec(graphRootURL: graphRootURL)
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    let fileURL = codec.fileURL(in: pagesRootURL, for: "Alpha/Beta")

    XCTAssertEqual(codec.format, .legacy)
    XCTAssertEqual(fileURL.lastPathComponent, "Alpha%2FBeta.md")
    XCTAssertTrue(codec.requiresExplicitTitleProperty(pageTitle: "Alpha/Beta"))
  }

  func testOwnedPageRenameMovesFileAndKeepsReminderOwnershipMetadata() async throws {
    let graphRootURL = try makeGraphRoot(named: "RenameGraph")
    let store = LogseqProjectPageStore(
      pagesRootURL: graphRootURL.appendingPathComponent("pages", isDirectory: true)
    )
    let projectID = UUID()

    _ = try await store.upsertPage(
      .init(
        projectID: projectID,
        title: "Old Title",
        reminderListExternalIdentifier: "reminder-list-1"
      ),
      noteMarkdown: "Intro",
      managedTasks: [
        .init(
          taskID: UUID(),
          title: "Keep me",
          isCompleted: false
        )
      ]
    )

    let oldURL = graphRootURL
      .appendingPathComponent("pages", isDirectory: true)
      .appendingPathComponent("Old Title.md", isDirectory: false)
    XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))

    _ = try await store.upsertPage(
      .init(
        projectID: projectID,
        title: "New Title",
        reminderListExternalIdentifier: "reminder-list-1"
      ),
      noteMarkdown: "Intro",
      managedTasks: [
        .init(
          taskID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"),
          title: "Keep me",
          isCompleted: false
        )
      ]
    )

    let newURL = graphRootURL
      .appendingPathComponent("pages", isDirectory: true)
      .appendingPathComponent("New Title.md", isDirectory: false)
    XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))

    let loaded = try await store.loadProjectPage(
      for: .init(
        projectID: projectID,
        title: "New Title",
        reminderListExternalIdentifier: "reminder-list-1"
      )
    )
    XCTAssertEqual(loaded?.fileURL.standardizedFileURL, newURL.standardizedFileURL)
    XCTAssertEqual(loaded?.projectID, nil)
    XCTAssertEqual(loaded?.reminderListExternalIdentifier, "reminder-list-1")
    XCTAssertEqual(loaded?.title, "New Title")
  }

  func testClaimTaggedPageAddsReminderOwnershipMetadataToInScopePage() async throws {
    let graphRootURL = try makeGraphRoot(named: "ClaimTaggedPageGraph")
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRootURL, withIntermediateDirectories: true)

    let pageURL = pagesRootURL.appendingPathComponent("Claim Me.md", isDirectory: false)
    try """
    tags:: 프로젝트

    Intro
    """.write(to: pageURL, atomically: true, encoding: .utf8)

    let store = LogseqProjectPageStore(pagesRootURL: pagesRootURL)
    let projectID = UUID()
    let taskID = UUID()

    _ = try await store.claimTaggedPage(
      at: pageURL,
      as: .init(
        projectID: projectID,
        title: "Claim Me",
        reminderListExternalIdentifier: "reminder-list-1"
      ),
      noteMarkdown: "Intro",
      managedTasks: [
        .init(
          taskID: taskID,
          title: "Imported task",
          isCompleted: false,
          reminderExternalIdentifier: "reminder-1"
        )
      ]
    )

    let loaded = try await store.loadProjectPage(
      for: .init(
        projectID: projectID,
        title: "Claim Me",
        reminderListExternalIdentifier: "reminder-list-1"
      )
    )

    XCTAssertEqual(loaded?.projectID, nil)
    XCTAssertEqual(loaded?.reminderListExternalIdentifier, "reminder-list-1")
    XCTAssertEqual(loaded?.managedTasks.count, 0)
    XCTAssertEqual(loaded?.externalTasks.count, 1)
    XCTAssertEqual(loaded?.externalTasks.first?.taskID, taskID)
  }

  func testReminderListIdentityAloneKeepsPageInScope() async throws {
    let graphRootURL = try makeGraphRoot(named: "ReminderOnlyScopeGraph")
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRootURL, withIntermediateDirectories: true)

    let pageURL = pagesRootURL.appendingPathComponent("Reminder Only.md", isDirectory: false)
    try """
    reminder_list_external_id:: reminder-list-1

    Imported from Reminders
    """.write(to: pageURL, atomically: true, encoding: .utf8)

    let store = LogseqProjectPageStore(pagesRootURL: pagesRootURL)
    let pages = try await store.loadProjectPagesInScope()

    XCTAssertEqual(pages.map(\.title), ["Reminder Only"])
    XCTAssertEqual(pages.first?.projectID, nil)
    XCTAssertEqual(pages.first?.reminderListExternalIdentifier, "reminder-list-1")
    XCTAssertEqual(pages.first?.isBUFOwned, true)
  }

  func testClaimTaggedPageRejectsReadOnlyTaskImportPage() async throws {
    let graphRootURL = try makeGraphRoot(named: "ClaimReadOnlyGraph")
    let pagesRootURL = graphRootURL.appendingPathComponent("pages", isDirectory: true)
    try FileManager.default.createDirectory(at: pagesRootURL, withIntermediateDirectories: true)

    let pageURL = pagesRootURL.appendingPathComponent("Read Only Claim.md", isDirectory: false)
    try """
    tags:: 프로젝트

    - TODO Imported task
    """.write(to: pageURL, atomically: true, encoding: .utf8)

    let store = LogseqProjectPageStore(pagesRootURL: pagesRootURL)

    do {
      _ = try await store.claimTaggedPage(
        at: pageURL,
        as: .init(
          projectID: UUID(),
          title: "Read Only Claim",
          reminderListExternalIdentifier: "reminder-list-1"
        ),
        noteMarkdown: "",
        managedTasks: []
      )
      XCTFail("Expected claim to be rejected for a page that still keeps unmanaged tasks outside the managed section")
    } catch let error as LogseqProjectPageStore.StoreError {
      switch error {
      case .managedSectionUnavailable:
        break
      default:
        XCTFail("Unexpected store error: \(error)")
      }
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
}
