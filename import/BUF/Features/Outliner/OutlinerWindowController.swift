import AppKit
import SwiftUI

@MainActor
final class OutlinerWindowController: NSWindowController, NSWindowDelegate {
  var onWillClose: ((OutlinerWindowController) -> Void)?

  init(appState: AppState) {
    let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    let window = NSWindow(contentViewController: hostingController)
    window.title = "아웃라이너"
    window.setContentSize(NSSize(width: projectDetailDetachedWindowContentWidth, height: 780))
    window.contentMinSize = NSSize(width: projectDetailDetachedWindowContentWidth, height: 560)
    window.contentMaxSize = NSSize(
      width: projectDetailDetachedWindowContentWidth,
      height: CGFloat.greatestFiniteMagnitude
    )
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.titleVisibility = .visible
    window.titlebarAppearsTransparent = true
    window.backgroundColor = .white
    window.isReleasedWhenClosed = false
    super.init(window: window)

    shouldCascadeWindows = true
    window.delegate = self
    updateRootView(appState: appState)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present(appState: AppState) {
    updateRootView(appState: appState)
    appState.platformUIFoundation.windowManager.activateApp()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    onWillClose?(self)
  }

  func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
    let currentContentHeight = sender.contentRect(forFrameRect: sender.frame).height
    let fixedFrameWidth = sender.frameRect(
      forContentRect: NSRect(
        x: 0,
        y: 0,
        width: projectDetailDetachedWindowContentWidth,
        height: currentContentHeight
      )
    ).width
    return NSSize(width: fixedFrameWidth, height: frameSize.height)
  }

  private func updateRootView(appState: AppState) {
    (window?.contentViewController as? NSHostingController<AnyView>)?.rootView = AnyView(
      OutlinerView()
        .environmentObject(appState)
    )
  }
}
