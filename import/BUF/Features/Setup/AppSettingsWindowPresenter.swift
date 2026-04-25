import AppKit
import SwiftUI

@MainActor
final class AppSettingsWindowPresenter: NSObject {
  static let shared = AppSettingsWindowPresenter()
  static let settingsMenuItemTag = 0x42554601

  private var window: NSWindow?
  private weak var appState: AppState?

  private override init() {}

  func register(appState: AppState) {
    self.appState = appState
  }

  func installAppMenuItem(appState: AppState) {
    register(appState: appState)
    installAppMenuItem()
  }

  func installAppMenuItem() {
    guard let appMenuItem = NSApp.mainMenu?.items.first,
      let appMenu = appMenuItem.submenu
    else {
      return
    }

    appMenuItem.title = "Brain Unfog"
    if let existingItem = appMenu.item(withTag: Self.settingsMenuItemTag) {
      existingItem.target = self
      existingItem.action = #selector(showSettingsFromMenu(_:))
      return
    }
    if appMenu.items.contains(where: { item in
      item.title == "설정..." || item.title.localizedCaseInsensitiveContains("settings")
    }) {
      return
    }

    let item = NSMenuItem(
      title: "설정...",
      action: #selector(showSettingsFromMenu(_:)),
      keyEquivalent: ","
    )
    item.keyEquivalentModifierMask = [.command]
    item.target = self
    item.tag = Self.settingsMenuItemTag
    appMenu.insertItem(item, at: settingsInsertIndex(in: appMenu))
  }

  func show(appState: AppState) {
    if let window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let hostingController = NSHostingController(
      rootView: AppSettingsView()
        .environmentObject(appState)
    )
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Brain Unfog 설정"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    window.center()
    self.window = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  @objc private func showSettingsFromMenu(_ sender: Any?) {
    guard let appState else { return }
    show(appState: appState)
  }

  private func settingsInsertIndex(in menu: NSMenu) -> Int {
    if let aboutIndex = menu.items.firstIndex(where: { item in
      item.title.localizedCaseInsensitiveContains("about")
        || item.title.localizedCaseInsensitiveContains("정보")
    }) {
      return min(aboutIndex + 1, menu.items.count)
    }

    if let servicesIndex = menu.items.firstIndex(where: { item in
      item.title.localizedCaseInsensitiveContains("services")
        || item.title.localizedCaseInsensitiveContains("서비스")
    }) {
      return servicesIndex
    }

    return 0
  }
}
