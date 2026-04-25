import AppKit
import SwiftUI

@MainActor
final class MainAppWindowPresenter: NSObject {
  static let shared = MainAppWindowPresenter()

  private var window: NSWindow?

  private override init() {}

  func show(appState: AppState) {
    if let window = reusableWindow() {
      self.window = window
      bringForward(window)
      closeDuplicateMainWindows(keeping: window)
      return
    }

    let hostingController = NSHostingController(
      rootView: RootSceneView()
        .environmentObject(appState)
    )
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Brain Unfog"
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(NSSize(width: 1280, height: 820))
    window.minSize = NSSize(width: 920, height: 620)
    window.isReleasedWhenClosed = false
    window.center()
    self.window = window

    bringForward(window)
  }

  func reassertSingleWindow(appState: AppState) {
    Task { @MainActor in
      for delay in [250, 1_000, 2_500] {
        try? await Task.sleep(for: .milliseconds(delay))
        show(appState: appState)
      }
    }
  }

  private func reusableWindow() -> NSWindow? {
    if let window, window.isVisible {
      return window
    }

    return NSApp.windows.first { candidate in
      candidate.title == "Brain Unfog" && candidate.isVisible
    }
  }

  private func bringForward(_ window: NSWindow) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func closeDuplicateMainWindows(keeping keptWindow: NSWindow) {
    for candidate in NSApp.windows where candidate !== keptWindow {
      guard candidate.title == "Brain Unfog" else { continue }
      candidate.close()
    }
  }
}
