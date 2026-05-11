import AppKit
import SwiftUI

extension NSUserInterfaceItemIdentifier {
  static let timelineProjectListWindow = NSUserInterfaceItemIdentifier(
    "timelineProjectListWindow"
  )
}

@MainActor
final class TimelineProjectListWindowPresenter {
  static let shared = TimelineProjectListWindowPresenter()

  private var windowRecords: [WindowRecord] = []

  private init() {}

  var presentedProjectIDs: [UUID] {
    pruneClosedWindows()
    return windowRecords.compactMap { record in
      guard Self.isLiveWindow(record.window) else { return nil }
      return Self.projectID(for: record.window)
    }
  }

  static func configureWindowLevel(_ window: NSWindow) {
    window.level = .floating
    if let panel = window as? NSPanel {
      panel.isFloatingPanel = true
      panel.hidesOnDeactivate = true
    }
  }

  @discardableResult
  static func clearInitialTextFocus(in window: NSWindow) -> Bool {
    guard shouldClearInitialFocus(window.firstResponder) else {
      return false
    }
    return window.makeFirstResponder(nil)
  }

  static func shouldClearInitialFocus(_ responder: NSResponder?) -> Bool {
    responder is NSTextView || responder is NSTextField
  }

  func present(
    snapshot: TimelineProjectListWindowSnapshot,
    onToggleTaskCompletion: @escaping (UUID, Bool) async -> Bool,
    onEditTask: @escaping (UUID) -> Void,
    onReorderTasks: @escaping (UUID, [UUID], Bool) -> Void,
    onCreateTask: @escaping (UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onRenameTask: @escaping (UUID, UUID, String) async -> TimelineProjectListWindowSnapshot.Task?,
    onDeleteTask: @escaping (UUID, UUID) async -> Bool,
    onRenameProject: @escaping (UUID, String) -> Void,
    onSaveProjectNote: @escaping (UUID, String) async -> String? = { _, _ in nil }
  ) {
    present(
      snapshot: snapshot,
      actions: TimelineProjectListActions(
        onToggleTaskCompletion: onToggleTaskCompletion,
        onEditTask: onEditTask,
        onReorderTasks: onReorderTasks,
        onCreateTask: onCreateTask,
        onRenameTask: onRenameTask,
        onDeleteTask: onDeleteTask,
        onRenameProject: onRenameProject,
        onSaveProjectNote: onSaveProjectNote
      )
    )
  }

  func present(
    snapshot: TimelineProjectListWindowSnapshot,
    actions: TimelineProjectListActions
  ) {
    let content = TimelineProjectListContent(
      snapshot: snapshot,
      presentation: .window,
      actions: actions
    )

    pruneClosedWindows()
    let hostingController = NSHostingController(rootView: content)
    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.identifier = .timelineProjectListWindow
    window.title = snapshot.title
    window.contentViewController = hostingController
    window.isReleasedWhenClosed = false
    Self.configureWindowLevel(window)
    window.setFrameAutosaveName("TimelineProjectListWindow")
    positionNewWindow(window)

    let recordID = UUID()
    let delegate = ProjectListWindowDelegate { [weak self] in
      self?.removeWindowRecord(id: recordID)
    }
    window.delegate = delegate
    windowRecords.append(WindowRecord(id: recordID, window: window, delegate: delegate))

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    Self.clearInitialTextFocus(in: window)
    DispatchQueue.main.async { [weak window] in
      guard let window else { return }
      Self.clearInitialTextFocus(in: window)
    }
  }

  @discardableResult
  func refresh(snapshot: TimelineProjectListWindowSnapshot) -> Int {
    pruneClosedWindows()
    var refreshedCount = 0
    for record in windowRecords where Self.isLiveWindow(record.window) {
      guard
        let hostingController = record.window.contentViewController
          as? NSHostingController<TimelineProjectListContent>,
        hostingController.rootView.snapshot.projectID == snapshot.projectID,
        hostingController.rootView.snapshot != snapshot
      else {
        continue
      }

      record.window.title = snapshot.title
      hostingController.rootView = hostingController.rootView.replacing(snapshot: snapshot)
      refreshedCount += 1
    }
    return refreshedCount
  }

  func closeAllWindows() {
    let records = windowRecords
    windowRecords.removeAll()
    for record in records {
      record.window.close()
    }
  }

  private func positionNewWindow(_ window: NSWindow) {
    guard let anchorWindow = windowRecords.last(where: { Self.isLiveWindow($0.window) })?.window else {
      window.center()
      return
    }

    let anchorOrigin = anchorWindow.frame.origin
    let nextOrigin = NSPoint(x: anchorOrigin.x + 28, y: max(anchorOrigin.y - 28, 80))
    window.setFrameOrigin(nextOrigin)
  }

  private func pruneClosedWindows() {
    windowRecords.removeAll { !Self.isLiveWindow($0.window) }
  }

  private func removeWindowRecord(id: UUID) {
    windowRecords.removeAll { $0.id == id }
  }

  private static func isLiveWindow(_ window: NSWindow) -> Bool {
    window.isVisible || window.isMiniaturized
  }

  private static func projectID(for window: NSWindow) -> UUID? {
    guard
      let hostingController = window.contentViewController
        as? NSHostingController<TimelineProjectListContent>
    else {
      return nil
    }
    return hostingController.rootView.snapshot.projectID
  }

  private struct WindowRecord {
    let id: UUID
    let window: NSWindow
    let delegate: ProjectListWindowDelegate
  }

  private final class ProjectListWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
      self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
      onClose()
    }
  }
}
