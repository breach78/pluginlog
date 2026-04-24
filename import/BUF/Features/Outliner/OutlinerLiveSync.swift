import Combine
import Foundation

struct OutlinerLiveReminderSnapshot: Identifiable {
  let contentID: UUID
  let reminderIdentifier: String
  let reminderExternalIdentifier: String?
  let calendarIdentifier: String
  let calendarTitle: String
  let rawPreservationPayloadRaw: String?
  let title: String
  let encodedNote: String
  let parsedBody: String
  let dueDateText: String
  let recurrenceText: String
  let requiredWorkDays: Int
  let isCompleted: Bool
  let completionDate: Date?
  let lastModifiedText: String
  let lastModifiedAt: Date?
  let restoredAppSnippetText: String
  let dueDate: Date?
  let hasExplicitTime: Bool
  let recurrence: OutlinerRecurrenceSample?
  let priority: Int

  var id: String { reminderIdentifier }
}

struct OutlinerRemoteReminderImport: Identifiable {
  let contentID: UUID?
  let reminderIdentifier: String
  let reminderExternalIdentifier: String?
  let calendarIdentifier: String
  let rawPreservationPayloadRaw: String?
  let title: String
  let encodedNote: String
  let parsedBody: String
  let dueDateText: String
  let recurrenceText: String
  let requiredWorkDays: Int
  let isCompleted: Bool
  let completionDate: Date?
  let lastModifiedText: String
  let lastModifiedAt: Date?
  let dueDate: Date?
  let hasExplicitTime: Bool
  let recurrence: OutlinerRecurrenceSample?
  let priority: Int

  var id: String { reminderIdentifier }
}

enum OutlinerRemoteSyncPolicy {
  static func shouldDeferLocalPush(
    hasFocusedNode: Bool,
    isProjectTitleFocused: Bool
  ) -> Bool {
    hasFocusedNode || isProjectTitleFocused
  }
}

@MainActor
final class OutlinerLiveSyncController: ObservableObject {
  @Published private(set) var syncListStatus: String = "AppState source-owned"
  @Published private(set) var statusMessage: String?
  @Published private(set) var errorMessage: String?
  @Published private(set) var isWorking = false
  @Published private(set) var currentSnapshot: OutlinerLiveReminderSnapshot?

  private var snapshotsByContentID: [UUID: OutlinerLiveReminderSnapshot] = [:]
  private var lastLocalWriteDatesByReminderIdentifier: [String: Date] = [:]
  private var currentProjectionContentID: UUID?

  func present(projection: OutlinerReminderProjection?) {
    guard let projection else {
      currentProjectionContentID = nil
      currentSnapshot = nil
      errorMessage = nil
      return
    }

    let contentID = projection.contentID
    currentProjectionContentID = contentID
    currentSnapshot = snapshotsByContentID[contentID]
    errorMessage = nil
  }

  func snapshot(forContentID contentID: UUID) -> OutlinerLiveReminderSnapshot? {
    snapshotsByContentID[contentID]
  }

  func installSnapshot(_ snapshot: OutlinerLiveReminderSnapshot) {
    snapshotsByContentID[snapshot.contentID] = snapshot
    if currentProjectionContentID == snapshot.contentID {
      currentSnapshot = snapshot
    }
  }

  func linkedReminderSummary(for projection: OutlinerReminderProjection?) -> String {
    guard let projection else { return "-" }
    guard let reminderIdentifier = linkedReminderIdentifier(for: projection),
      !reminderIdentifier.isEmpty
    else {
      return "없음"
    }
    return shortIdentifier(reminderIdentifier)
  }

  func linkedReminderIdentifier(for projection: OutlinerReminderProjection) -> String? {
    snapshotsByContentID[projection.contentID]?.reminderIdentifier
      ?? normalizedIdentifier(projection.reminderIdentifier)
  }

  func normalizeMirrorState(validContentIDs: Set<UUID>) {
    snapshotsByContentID = snapshotsByContentID.filter {
      validContentIDs.contains($0.key)
    }

    if let currentProjectionContentID {
      currentSnapshot = snapshotsByContentID[currentProjectionContentID]
    }
  }

  func unlinkProjection(_ projection: OutlinerReminderProjection) {
    unlinkContentID(projection.contentID)
  }

  func unlinkContentID(_ contentID: UUID) {
    if let removedIdentifier = snapshotsByContentID.removeValue(forKey: contentID)?.reminderIdentifier {
      lastLocalWriteDatesByReminderIdentifier.removeValue(forKey: removedIdentifier)
    }
    if currentProjectionContentID == contentID {
      currentSnapshot = nil
    }
  }

  func rebind(
    from previousProjection: OutlinerReminderProjection,
    to updatedProjection: OutlinerReminderProjection
  ) {
    let previousContentID = previousProjection.contentID
    let updatedContentID = updatedProjection.contentID
    guard previousContentID != updatedContentID else { return }

    if let snapshot = snapshotsByContentID.removeValue(forKey: previousContentID) {
      snapshotsByContentID[updatedContentID] = snapshot
      currentSnapshot = snapshot
    }
    if currentProjectionContentID == previousContentID {
      currentProjectionContentID = updatedContentID
    }
  }

  func publishStatusMessage(_ message: String) {
    statusMessage = message
  }

  func lastLocalWriteDate(for reminderIdentifier: String) -> Date? {
    lastLocalWriteDatesByReminderIdentifier[reminderIdentifier]
  }

  func fetchRemoteReminderIndex(
    for projections: [OutlinerReminderProjection],
    appState: AppState
  ) async -> [UUID: OutlinerRemoteReminderImport] {
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }

    do {
      let linkedReminderIdentifiersByContentID = projections.reduce(into: [UUID: String]()) {
        result,
        projection in
        if let reminderIdentifier = linkedReminderIdentifier(for: projection) {
          result[projection.contentID] = reminderIdentifier
        }
      }
      return try await appState.fetchOutlinerRemoteReminderIndex(
        for: projections,
        linkedReminderIdentifiersByContentID: linkedReminderIdentifiersByContentID
      )
    } catch {
      errorMessage = error.localizedDescription
      return [:]
    }
  }

  func saveProjection(
    _ projection: OutlinerReminderProjection,
    calendarIdentifier: String?,
    encodedNoteOverride: String? = nil,
    pendingOperationRecord: ReminderSyncPendingOperationRecord? = nil,
    appState: AppState
  ) async -> OutlinerLiveReminderSnapshot? {
    isWorking = true
    statusMessage = nil
    errorMessage = nil
    defer { isWorking = false }

    do {
      let snapshot = try await appState.saveOutlinerReminderProjection(
        projection,
        linkedReminderIdentifier: linkedReminderIdentifier(for: projection),
        calendarIdentifier: calendarIdentifier,
        encodedNoteOverride: encodedNoteOverride,
        pendingOperationRecord: pendingOperationRecord
      )
      recordLocalWrite(for: snapshot.reminderIdentifier)
      installSnapshot(snapshot)
      statusMessage = "선택 task를 리마인더에 저장했습니다."
      return snapshot
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  func saveProjectionMetadata(
    _ projection: OutlinerReminderProjection,
    calendarIdentifier: String?,
    metadataPlanOverride: ReminderMetadataMutationPlan? = nil,
    appState: AppState
  ) async -> OutlinerLiveReminderSnapshot? {
    isWorking = true
    statusMessage = nil
    errorMessage = nil
    defer { isWorking = false }

    do {
      let snapshot = try await appState.saveOutlinerReminderProjectionMetadata(
        projection,
        linkedReminderIdentifier: linkedReminderIdentifier(for: projection),
        calendarIdentifier: calendarIdentifier,
        metadataPlanOverride: metadataPlanOverride
      )
      recordLocalWrite(for: snapshot.reminderIdentifier)
      installSnapshot(snapshot)
      statusMessage = "리마인더 메타데이터를 저장했습니다."
      return snapshot
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  func refreshProjection(
    _ projection: OutlinerReminderProjection,
    appState: AppState
  ) async -> OutlinerLiveReminderSnapshot? {
    isWorking = true
    statusMessage = nil
    errorMessage = nil
    defer { isWorking = false }

    do {
      guard let snapshot = try await appState.refreshOutlinerReminderProjection(
        projection,
        linkedReminderIdentifier: linkedReminderIdentifier(for: projection)
      ) else {
        currentSnapshot = nil
        statusMessage = "아직 연결된 리마인더가 없어 새로고칠 대상이 없습니다."
        return nil
      }

      installSnapshot(snapshot)
      statusMessage = "리마인더에서 최신 내용을 다시 읽었습니다."
      return snapshot
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  func bindImportedReminder(
    _ remoteImport: OutlinerRemoteReminderImport,
    to projection: OutlinerReminderProjection
  ) {
    let contentID = projection.contentID
    installSnapshot(
      OutlinerLiveReminderSnapshot(
        contentID: contentID,
        reminderIdentifier: remoteImport.reminderIdentifier,
        reminderExternalIdentifier: remoteImport.reminderExternalIdentifier,
        calendarIdentifier: remoteImport.calendarIdentifier,
        calendarTitle: OutlinerReminderProjectionBuilder.syncListName,
        rawPreservationPayloadRaw: remoteImport.rawPreservationPayloadRaw,
        title: remoteImport.title,
        encodedNote: remoteImport.encodedNote,
        parsedBody: remoteImport.parsedBody,
        dueDateText: remoteImport.dueDateText,
        recurrenceText: remoteImport.recurrenceText,
        requiredWorkDays: remoteImport.requiredWorkDays,
        isCompleted: remoteImport.isCompleted,
        completionDate: remoteImport.completionDate,
        lastModifiedText: remoteImport.lastModifiedText,
        lastModifiedAt: remoteImport.lastModifiedAt,
        restoredAppSnippetText: OutlinerReminderProjectionBuilder.restoredAppSnippetText(
          for: projection,
          reminderTitle: remoteImport.title,
          reminderBody: remoteImport.parsedBody
        ),
        dueDate: remoteImport.dueDate,
        hasExplicitTime: remoteImport.hasExplicitTime,
        recurrence: remoteImport.recurrence,
        priority: remoteImport.priority
      )
    )
  }

  private func recordLocalWrite(for reminderIdentifier: String, now: Date = .now) {
    lastLocalWriteDatesByReminderIdentifier[reminderIdentifier] = now
  }

  private func shortIdentifier(_ identifier: String) -> String {
    let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 10 else { return trimmed }
    return String(trimmed.prefix(10)) + "…"
  }

  private func normalizedIdentifier(_ value: String?) -> String? {
    value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? value?.trimmingCharacters(in: .whitespacesAndNewlines)
      : nil
  }
}
