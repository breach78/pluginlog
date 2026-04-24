import AppKit
import Foundation

extension AppState {
  func refreshCurrentDayBoundaryIfNeeded(referenceDate: Date = .now, force: Bool = false) {
    let nextDayStart = Calendar.autoupdatingCurrent.startOfDay(for: referenceDate)
    let didChange = nextDayStart != currentDayStart
    guard force || didChange else {
      scheduleNextDayBoundaryTimer(from: nextDayStart)
      return
    }

    currentDayStart = nextDayStart
    currentDayChangeToken += 1
    scheduleNextDayBoundaryTimer(from: nextDayStart)
  }

  func configureDayBoundaryObservation() {
    scheduleNextDayBoundaryTimer(from: currentDayStart)

    let notificationCenter = NotificationCenter.default
    dayBoundaryObservers.append(
      notificationCenter.addObserver(
        forName: Self.calendarDayChangedNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.refreshCurrentDayBoundaryIfNeeded()
        }
      })
    dayBoundaryObservers.append(
      notificationCenter.addObserver(
        forName: Self.systemClockDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.refreshCurrentDayBoundaryIfNeeded()
        }
      })
    dayBoundaryObservers.append(
      notificationCenter.addObserver(
        forName: Self.systemTimeZoneDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.refreshCurrentDayBoundaryIfNeeded()
        }
      })
    dayBoundaryObservers.append(
      notificationCenter.addObserver(
        forName: NSApplication.didBecomeActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.refreshCurrentDayBoundaryIfNeeded()
          self?.sweepReminderSyncEditSessionsIfNeeded()
        }
      })
    dayBoundaryObservers.append(
      notificationCenter.addObserver(
        forName: NSWindow.willCloseNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        let ownerWindowID = Self.reminderSyncOwnerWindowID(from: notification.object as? NSWindow)
        Task { @MainActor in
          if let ownerWindowID {
            self?.reminderSyncEditGate?.cancelSessionsOwnedByWindow(ownerWindowID)
          }
        }
      })

    let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
    workspaceDayBoundaryObservers.append(
      workspaceNotificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.refreshCurrentDayBoundaryIfNeeded()
          self?.sweepReminderSyncEditSessionsIfNeeded()
        }
      })
  }

  func notifyEditorActivity() {
    editorIdleDeadline = Date().addingTimeInterval(0.9)
    activateEditorMotionSuppression()
    setEditorActive(true)
    reminderSyncEditGate?.heartbeatAllSessions()
    startEditorIdleMonitorIfNeeded()
  }

  func beginEditorSession(
    id: String,
    syncRelevant: Bool = false,
    syncKind: ReminderSyncEditGate.SessionKind = .generic,
    contentID: UUID? = nil,
    projectID: UUID? = nil,
    ownerWindowID: String? = nil
  ) {
    activeExplicitEditorSessionIDs.insert(id)
    activateEditorMotionSuppression()
    setEditorActive(true)
    if syncRelevant {
      reminderSyncEditGate?.beginSession(
        sessionID: id,
        ownerWindowID: ownerWindowID ?? resolvedReminderSyncOwnerWindowID(),
        kind: syncKind,
        contentID: contentID,
        projectID: projectID
      )
    }
    startEditorIdleMonitorIfNeeded()
  }

  func endEditorSession(id: String) {
    activeExplicitEditorSessionIDs.remove(id)
    reminderSyncEditGate?.endSession(sessionID: id)

    guard activeExplicitEditorSessionIDs.isEmpty else { return }
    guard Date() >= editorIdleDeadline else {
      startEditorIdleMonitorIfNeeded()
      return
    }

    if isEditorActive {
      setEditorActive(false)
      scheduleEditorMotionReleaseIfNeeded()
    }
  }

  func waitForEditorToBecomeIdle(after delay: Duration = .zero) async -> Bool {
    do {
      try await Task.sleep(for: delay)
    } catch {
      return false
    }

    guard !Task.isCancelled else { return false }
    guard isEditorActive else { return true }

    let stateChanges = makeEditorStateChangeStream()
    if !isEditorActive {
      return true
    }

    for await _ in stateChanges {
      guard !Task.isCancelled else { return false }
      if !isEditorActive {
        return true
      }
    }

    return !isEditorActive && !Task.isCancelled
  }

  private func scheduleNextDayBoundaryTimer(from dayStart: Date) {
    dayBoundaryTimer?.invalidate()

    let calendar = Calendar.autoupdatingCurrent
    let nextBoundary = calendar.date(byAdding: .day, value: 1, to: dayStart)
      ?? dayStart.addingTimeInterval(24 * 60 * 60)
    let interval = max(1, nextBoundary.timeIntervalSinceNow)
    let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
      Task { @MainActor in
        self?.refreshCurrentDayBoundaryIfNeeded()
      }
    }
    dayBoundaryTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func startEditorIdleMonitorIfNeeded() {
    guard editorIdleTask == nil else { return }

    editorIdleTask = Task { @MainActor [weak self] in
      while let self, !Task.isCancelled {
        do {
          try await Task.sleep(for: .milliseconds(180))
        } catch {
          break
        }

        guard self.isEditorActive else { break }
        guard self.activeExplicitEditorSessionIDs.isEmpty else { continue }
        if Date() >= self.editorIdleDeadline {
          self.setEditorActive(false)
          self.scheduleEditorMotionReleaseIfNeeded()
          break
        }
      }

      self?.editorIdleTask = nil
    }
  }

  private func activateEditorMotionSuppression() {
    editorMotionReleaseTask?.cancel()
    editorMotionReleaseTask = nil
    if !isEditorMotionSuppressed {
      isEditorMotionSuppressed = true
    }
  }

  private func scheduleEditorMotionReleaseIfNeeded() {
    editorMotionReleaseTask?.cancel()

    guard isEditorMotionSuppressed else {
      editorMotionReleaseTask = nil
      return
    }

    editorMotionReleaseTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: self?.editorMotionReleaseDelay ?? .milliseconds(260))
      } catch {
        return
      }

      guard let self else { return }
      guard !Task.isCancelled else { return }
      guard !self.isEditorActive else {
        self.editorMotionReleaseTask = nil
        return
      }
      guard self.activeExplicitEditorSessionIDs.isEmpty else {
        self.editorMotionReleaseTask = nil
        return
      }

      self.isEditorMotionSuppressed = false
      self.editorMotionReleaseTask = nil
    }
  }

  private func setEditorActive(_ isActive: Bool) {
    guard isEditorActive != isActive else { return }
    isEditorActive = isActive
    notifyEditorStateChanged()
  }

  private func makeEditorStateChangeStream() -> AsyncStream<Void> {
    let id = UUID()
    return AsyncStream { continuation in
      editorStateChangeContinuations[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.editorStateChangeContinuations.removeValue(forKey: id)
        }
      }
    }
  }

  private func notifyEditorStateChanged() {
    for continuation in editorStateChangeContinuations.values {
      continuation.yield(())
    }
  }

  func sweepReminderSyncEditSessionsIfNeeded(now: Date = .now) {
    guard let reminderSyncEditGate else { return }

    let result = reminderSyncEditGate.sweepOrphanedSessions(
      activeOwnerWindowIDs: activeReminderSyncOwnerWindowIDs(),
      now: now
    )

    guard result.forcedManualRevalidateCount > 0 else { return }
    AppLogger.sync.error(
      """
      forced reminder sync gate cancel required manual revalidate. \
      cancelledSessions=\(result.cancelledSessionIDs.joined(separator: ","), privacy: .public) \
      count=\(result.forcedManualRevalidateCount, privacy: .public)
      """
    )
  }

  private func activeReminderSyncOwnerWindowIDs() -> Set<String> {
    guard let application = NSApp else { return [] }
    return Set(application.windows.compactMap(Self.reminderSyncOwnerWindowID(from:)))
  }

  private func resolvedReminderSyncOwnerWindowID() -> String? {
    Self.reminderSyncOwnerWindowID(from: NSApp.keyWindow ?? NSApp.mainWindow)
  }

  nonisolated private static func reminderSyncOwnerWindowID(from window: NSWindow?) -> String? {
    guard let window else { return nil }
    if let identifier = window.identifier?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines),
      !identifier.isEmpty
    {
      return identifier
    }
    return "window-\(window.windowNumber)"
  }
}
