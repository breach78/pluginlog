import AppKit
import SwiftUI

@MainActor
final class OpenAISettingsWindowController: NSWindowController {
  static let shared = OpenAISettingsWindowController()

  private init() {
    let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    let window = NSWindow(contentViewController: hostingController)
    window.title = "설정"
    window.setContentSize(NSSize(width: 600, height: 430))
    window.minSize = NSSize(width: 560, height: 380)
    window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    window.titleVisibility = .visible
    window.isReleasedWhenClosed = false
    super.init(window: window)
    shouldCascadeWindows = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show(appState: AppState) {
    guard let window else { return }
    let rootView = OpenAISettingsView()
      .environmentObject(appState)
    (window.contentViewController as? NSHostingController<AnyView>)?.rootView = AnyView(rootView)
    appState.platformUIFoundation.windowManager.activateApp()
    showWindow(nil)
    window.makeKeyAndOrderFront(nil)
  }
}
