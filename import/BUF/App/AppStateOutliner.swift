import AppKit

extension AppState {
  func openOutlinerWindow() {
    if focusOutlinerWindow() {
      return
    }

    let controller = OutlinerWindowController(appState: self)
    controller.onWillClose = { [weak self, weak controller] closedController in
      guard let self, let controller else { return }
      if self.outlinerWindowController === controller && controller === closedController {
        self.outlinerWindowController = nil
      }
    }
    outlinerWindowController = controller
    controller.present(appState: self)
  }

  @discardableResult
  func focusOutlinerWindow() -> Bool {
    guard let controller = outlinerWindowController else { return false }
    controller.present(appState: self)
    return true
  }

  func closeOutlinerWindow() {
    guard let controller = outlinerWindowController else { return }
    outlinerWindowController = nil
    controller.close()
  }
}
