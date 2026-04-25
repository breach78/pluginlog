import Foundation

struct ReminderPendingProjectBinding: Codable, Equatable, Sendable {
  var pagePath: String
  var pageTitleFingerprint: String
  var reminderListExternalIdentifier: String
  var createdAt: Date
}

struct ReminderPendingTaskBinding: Codable, Equatable, Sendable {
  var pagePath: String
  var listExternalIdentifier: String
  var taskIndex: Int
  var taskTitleFingerprint: String
  var taskFingerprint: String
  var reminderExternalIdentifier: String
  var createdAt: Date
}

private struct ReminderPendingBindingPayload: Codable, Equatable {
  var projectBindings: [ReminderPendingProjectBinding]
  var taskBindings: [ReminderPendingTaskBinding]

  static let empty = ReminderPendingBindingPayload(projectBindings: [], taskBindings: [])
}

enum ReminderPendingBindingStore {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var fileURL: URL?
  private nonisolated(unsafe) static var payload = ReminderPendingBindingPayload.empty
  private static let bindingTTL: TimeInterval = 24 * 60 * 60

  static func install(dataDirectory: URL?) {
    lock.lock()
    defer { lock.unlock() }
    fileURL = dataDirectory?.appendingPathComponent("retained-pending-reminder-bindings.json")
    loadLocked()
  }

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    fileURL = nil
    payload = .empty
  }

  static func projectBinding(
    pageFileURL: URL,
    pageTitle: String,
    now: Date
  ) -> ReminderPendingProjectBinding? {
    lock.lock()
    defer { lock.unlock() }
    pruneExpiredLocked(now: now)
    let pagePath = pageKey(for: pageFileURL)
    let titleFingerprint = fingerprint(pageTitle)
    return payload.projectBindings.first {
      $0.pagePath == pagePath
        && $0.pageTitleFingerprint == titleFingerprint
    }
  }

  static func hasProjectBindingForPage(
    pageFileURL: URL,
    now: Date
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    pruneExpiredLocked(now: now)
    let pagePath = pageKey(for: pageFileURL)
    return payload.projectBindings.contains { $0.pagePath == pagePath }
  }

  static func upsertProjectBinding(
    pageFileURL: URL,
    pageTitle: String,
    reminderListExternalIdentifier: String,
    now: Date
  ) {
    lock.lock()
    defer { lock.unlock() }
    pruneExpiredLocked(now: now)
    let binding = ReminderPendingProjectBinding(
      pagePath: pageKey(for: pageFileURL),
      pageTitleFingerprint: fingerprint(pageTitle),
      reminderListExternalIdentifier: reminderListExternalIdentifier,
      createdAt: now
    )
    payload.projectBindings.removeAll {
      $0.pagePath == binding.pagePath
        && $0.pageTitleFingerprint == binding.pageTitleFingerprint
    }
    payload.projectBindings.append(binding)
    persistLocked()
  }

  static func removeProjectBinding(
    pageFileURL: URL,
    pageTitle: String
  ) {
    lock.lock()
    defer { lock.unlock() }
    let pagePath = pageKey(for: pageFileURL)
    let titleFingerprint = fingerprint(pageTitle)
    payload.projectBindings.removeAll {
      $0.pagePath == pagePath
        && $0.pageTitleFingerprint == titleFingerprint
    }
    persistLocked()
  }

  static func taskBinding(
    pageFileURL: URL,
    listExternalIdentifier: String,
    taskIndex: Int,
    task: LogseqProjectPageStore.TaskRecord,
    now: Date
  ) -> ReminderPendingTaskBinding? {
    lock.lock()
    defer { lock.unlock() }
    pruneExpiredLocked(now: now)
    let pagePath = pageKey(for: pageFileURL)
    let taskFingerprint = fingerprint(for: task)
    return payload.taskBindings.first {
      $0.pagePath == pagePath
        && $0.listExternalIdentifier == listExternalIdentifier
        && $0.taskIndex == taskIndex
        && $0.taskFingerprint == taskFingerprint
    }
  }

  static func hasTaskBindingForPageListIndex(
    pageFileURL: URL,
    listExternalIdentifier: String,
    taskIndex: Int,
    now: Date
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    pruneExpiredLocked(now: now)
    let pagePath = pageKey(for: pageFileURL)
    return payload.taskBindings.contains {
      $0.pagePath == pagePath
        && $0.listExternalIdentifier == listExternalIdentifier
        && $0.taskIndex == taskIndex
    }
  }

  static func upsertTaskBinding(
    pageFileURL: URL,
    listExternalIdentifier: String,
    taskIndex: Int,
    task: LogseqProjectPageStore.TaskRecord,
    reminderExternalIdentifier: String,
    now: Date
  ) {
    lock.lock()
    defer { lock.unlock() }
    pruneExpiredLocked(now: now)
    let binding = ReminderPendingTaskBinding(
      pagePath: pageKey(for: pageFileURL),
      listExternalIdentifier: listExternalIdentifier,
      taskIndex: taskIndex,
      taskTitleFingerprint: fingerprint(task.title),
      taskFingerprint: fingerprint(for: task),
      reminderExternalIdentifier: reminderExternalIdentifier,
      createdAt: now
    )
    payload.taskBindings.removeAll {
      $0.pagePath == binding.pagePath
        && $0.listExternalIdentifier == binding.listExternalIdentifier
        && $0.taskIndex == binding.taskIndex
        && $0.taskFingerprint == binding.taskFingerprint
    }
    payload.taskBindings.append(binding)
    persistLocked()
  }

  static func removeTaskBinding(
    pageFileURL: URL,
    listExternalIdentifier: String,
    taskIndex: Int,
    task: LogseqProjectPageStore.TaskRecord
  ) {
    lock.lock()
    defer { lock.unlock() }
    let pagePath = pageKey(for: pageFileURL)
    let taskFingerprint = fingerprint(for: task)
    payload.taskBindings.removeAll {
      $0.pagePath == pagePath
        && $0.listExternalIdentifier == listExternalIdentifier
        && $0.taskIndex == taskIndex
        && $0.taskFingerprint == taskFingerprint
    }
    persistLocked()
  }

  private static func loadLocked() {
    guard let fileURL,
      let data = try? Data(contentsOf: fileURL),
      let decoded = try? JSONDecoder().decode(ReminderPendingBindingPayload.self, from: data)
    else {
      payload = .empty
      return
    }
    payload = decoded
  }

  private static func persistLocked() {
    guard let fileURL else { return }
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(payload)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      AppLogger.sync.error(
        "pending reminder binding persist failed: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private static func pruneExpiredLocked(now: Date) {
    payload.projectBindings.removeAll { now.timeIntervalSince($0.createdAt) > bindingTTL }
    payload.taskBindings.removeAll { now.timeIntervalSince($0.createdAt) > bindingTTL }
  }

  private static func pageKey(for fileURL: URL) -> String {
    fileURL.standardizedFileURL.path
  }

  private static func fingerprint(_ value: String) -> String {
    value
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .lowercased()
  }

  private static func fingerprint(for task: LogseqProjectPageStore.TaskRecord) -> String {
    [
      fingerprint(task.title),
      task.isCompleted ? "done" : "todo",
      fingerprint(task.date ?? ""),
      fingerprint(task.repeatRule ?? ""),
      fingerprint(task.noteText ?? ""),
    ].joined(separator: "|")
  }
}
