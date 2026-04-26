import AppKit
import Foundation

enum RemindersAppOpenServiceError: LocalizedError, Equatable {
  case projectReminderListNotFound(UUID)
  case taskReminderNotFound(UUID)
  case invalidScript
  case scriptFailed(String)

  var errorDescription: String? {
    switch self {
    case .projectReminderListNotFound(let projectID):
      return "Reminders에서 열 목록 연결을 찾지 못했습니다. \(projectID.uuidString)"
    case .taskReminderNotFound(let taskID):
      return "Reminders에서 열 할일 연결을 찾지 못했습니다. \(taskID.uuidString)"
    case .invalidScript:
      return "Reminders 열기 스크립트를 만들지 못했습니다."
    case .scriptFailed(let message):
      return "Reminders에서 항목을 열지 못했습니다. \(message)"
    }
  }
}

@MainActor
protocol RemindersAppScriptExecuting {
  func execute(_ source: String) throws
}

@MainActor
protocol RemindersAppPreparing {
  func prepareRemindersApp() async throws
}

@MainActor
final class AppleRemindersAppScriptExecutor: RemindersAppScriptExecuting {
  static let shared = AppleRemindersAppScriptExecutor()

  func execute(_ source: String) throws {
    guard let script = NSAppleScript(source: source) else {
      throw RemindersAppOpenServiceError.invalidScript
    }

    var errorInfo: NSDictionary?
    script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      let message =
        errorInfo[NSAppleScript.errorMessage] as? String
        ?? errorInfo.description
      throw RemindersAppOpenServiceError.scriptFailed(message)
    }
  }
}

@MainActor
final class AppleRemindersAppPreparer: RemindersAppPreparing {
  static let shared = AppleRemindersAppPreparer()
  private let bundleIdentifier = "com.apple.reminders"

  func prepareRemindersApp() async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.addsToRecentItems = false

    guard
      let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        ?? URL(string: "file:///System/Applications/Reminders.app")
    else {
      throw RemindersAppOpenServiceError.scriptFailed("Reminders.app을 찾지 못했습니다.")
    }

    let _: Void = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }

    for _ in 0..<12 {
      if isRemindersReady {
        return
      }
      try await Task.sleep(for: .milliseconds(200))
    }
  }

  private var isRemindersReady: Bool {
    NSRunningApplication
      .runningApplications(withBundleIdentifier: bundleIdentifier)
      .contains { !$0.isTerminated && $0.isFinishedLaunching }
  }
}

enum RemindersAppScripting {
  static func showListScript(listExternalIdentifier: String) -> String {
    """
    \(showPrefix)
      show list id \(appleScriptString(listExternalIdentifier))
    \(showSuffix)
    """
  }

  static func showReminderScript(reminderExternalIdentifier: String) -> String {
    """
    \(showPrefix)
      show reminder id \(appleScriptString(reminderAppleScriptID(for: reminderExternalIdentifier)))
    \(showSuffix)
    """
  }

  static func reminderAppleScriptID(for reminderExternalIdentifier: String) -> String {
    let normalized = reminderExternalIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.hasPrefix("x-apple-reminder://") {
      return normalized
    }
    return "x-apple-reminder://\(normalized)"
  }

  private static func appleScriptString(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  private static var showPrefix: String {
    """
    with timeout of 5 seconds
      tell application id "com.apple.reminders"
        activate
    """
  }

  private static var showSuffix: String {
    """
      end tell
    end timeout
    """
  }
}

@MainActor
enum RemindersAppOpenService {
  static func openProjectList(
    projectID: UUID,
    listExternalIdentifier preferredListExternalIdentifier: String? = nil,
    scriptExecutor: any RemindersAppScriptExecuting = AppleRemindersAppScriptExecutor.shared,
    appPreparer: any RemindersAppPreparing = AppleRemindersAppPreparer.shared
  ) async throws {
    let listExternalIdentifier =
      normalized(preferredListExternalIdentifier)
      ?? normalized(TaskIdentityBridgeStore.projectRecord(for: projectID)?.reminderListExternalIdentifier)
    guard let listExternalIdentifier else {
      throw RemindersAppOpenServiceError.projectReminderListNotFound(projectID)
    }

    try await executeAfterPreparingReminders(
      RemindersAppScripting.showListScript(listExternalIdentifier: listExternalIdentifier),
      scriptExecutor: scriptExecutor,
      appPreparer: appPreparer
    )
  }

  static func openTask(
    taskID: UUID,
    scriptExecutor: any RemindersAppScriptExecuting = AppleRemindersAppScriptExecutor.shared,
    appPreparer: any RemindersAppPreparing = AppleRemindersAppPreparer.shared
  ) async throws {
    guard
      let reminderExternalIdentifier = normalized(
        TaskIdentityBridgeStore.taskRecord(for: taskID)?.reminderExternalIdentifier
      )
    else {
      throw RemindersAppOpenServiceError.taskReminderNotFound(taskID)
    }

    try await executeAfterPreparingReminders(
      RemindersAppScripting.showReminderScript(
        reminderExternalIdentifier: reminderExternalIdentifier
      ),
      scriptExecutor: scriptExecutor,
      appPreparer: appPreparer
    )
  }

  private static func executeAfterPreparingReminders(
    _ source: String,
    scriptExecutor: any RemindersAppScriptExecuting,
    appPreparer: any RemindersAppPreparing
  ) async throws {
    try await appPreparer.prepareRemindersApp()
    do {
      try scriptExecutor.execute(source)
    } catch RemindersAppOpenServiceError.scriptFailed(let message)
      where shouldRetryAfterRunningError(message)
    {
      try await Task.sleep(for: .milliseconds(350))
      try await appPreparer.prepareRemindersApp()
      try scriptExecutor.execute(source)
    }
  }

  private static func shouldRetryAfterRunningError(_ message: String) -> Bool {
    let normalizedMessage = message.lowercased()
    return normalizedMessage.contains("isn't running")
      || normalizedMessage.contains("is not running")
      || normalizedMessage.contains("not running")
      || normalizedMessage.contains("실행")
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }
}
