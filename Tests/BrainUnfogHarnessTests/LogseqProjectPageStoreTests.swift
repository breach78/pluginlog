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
    XCTAssertTrue(fileContents.contains("brain_unfog_project_id:: \(projectID.uuidString.lowercased())"))
    XCTAssertTrue(fileContents.contains("## Brain Unfog Managed Tasks"))

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
    XCTAssertEqual(loaded?.noteMarkdown, "Intro line\n- plain bullet\n  continuation")
    XCTAssertEqual(
      loaded?.managedTasks,
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
    XCTAssertEqual(loaded?.hasManagedTaskSection, true)
    XCTAssertEqual(loaded?.externalTasks, [])
    XCTAssertEqual(loaded?.canSafelyPersistProjectNote, true)
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

    do {
      _ = try await store.upsertPage(
        .init(
          projectID: projectID,
          title: "Read Only Project",
          reminderListExternalIdentifier: "reminder-list-1"
        ),
        noteMarkdown: try XCTUnwrap(loaded).noteMarkdown,
        managedTasks: [
          .init(
            taskID: taskID,
            title: "Imported task",
            isCompleted: false
          )
        ]
      )
      XCTFail("Expected write to be blocked for a page that still keeps managed tasks outside the managed section")
    } catch let error as LogseqProjectPageStore.StoreError {
      switch error {
      case .managedSectionUnavailable:
        break
      default:
        XCTFail("Unexpected store error: \(error)")
      }
    }
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

  func testOwnedPageRenameMovesFileAndKeepsOwnershipMetadata() async throws {
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
    XCTAssertEqual(loaded?.projectID, projectID)
    XCTAssertEqual(loaded?.title, "New Title")
  }

  func testClaimTaggedPageAddsOwnershipMetadataToInScopePage() async throws {
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

    XCTAssertEqual(loaded?.projectID, projectID)
    XCTAssertEqual(loaded?.reminderListExternalIdentifier, "reminder-list-1")
    XCTAssertEqual(loaded?.managedTasks.count, 1)
    XCTAssertEqual(loaded?.managedTasks.first?.taskID, taskID)
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
