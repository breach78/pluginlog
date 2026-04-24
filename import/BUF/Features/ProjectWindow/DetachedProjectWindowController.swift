import AppKit
import SwiftData
import SwiftUI

let projectDetailDetachedWindowContentWidth: CGFloat = 720

@MainActor
final class DetachedProjectWindowController: NSWindowController, NSWindowDelegate {
  let projectID: UUID
  var onWillClose: ((DetachedProjectWindowController) -> Void)?

  init(
    projectID: UUID,
    appState: AppState,
    modelContainer: ModelContainer
  ) {
    self.projectID = projectID

    let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    let window = NSWindow(contentViewController: hostingController)
    window.title = "프로젝트 디테일"
    window.setContentSize(NSSize(width: projectDetailDetachedWindowContentWidth, height: 920))
    window.minSize = NSSize(width: 620, height: 420)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.titleVisibility = .visible
    window.isReleasedWhenClosed = false
    super.init(window: window)

    shouldCascadeWindows = true
    window.delegate = self
    updateRootView(appState: appState, modelContainer: modelContainer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present(appState: AppState, modelContainer: ModelContainer) {
    updateRootView(appState: appState, modelContainer: modelContainer)
    appState.platformUIFoundation.windowManager.activateApp()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    onWillClose?(self)
  }

  private func updateRootView(appState: AppState, modelContainer: ModelContainer) {
    let rootView: AnyView
    rootView = AnyView(
      ProjectDetailHostView(
        projectID: projectID,
        completedVisibilityStorageScope: "detachedProjectWindow.\(projectID.uuidString)",
        fixedWidth: nil,
        showsLeadingDivider: false
      )
    )

    (window?.contentViewController as? NSHostingController<AnyView>)?.rootView = AnyView(
      rootView
        .environmentObject(appState)
        .modelContainer(modelContainer)
    )
  }
}
