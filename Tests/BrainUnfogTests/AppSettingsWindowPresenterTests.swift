import AppKit
import SwiftUI
import XCTest
@testable import BrainUnfog

@MainActor
final class AppSettingsWindowPresenterTests: XCTestCase {
  func testInstallAppMenuItemAddsSettingsCommandToApplicationMenu() {
    let application = NSApplication.shared
    let previousMainMenu = application.mainMenu
    defer { application.mainMenu = previousMainMenu }

    let mainMenu = NSMenu()
    let appItem = NSMenuItem(title: "BrainUnfog", action: nil, keyEquivalent: "")
    let appMenu = NSMenu(title: "BrainUnfog")
    appMenu.addItem(NSMenuItem(title: "About Brain Unfog", action: nil, keyEquivalent: ""))
    appMenu.addItem(.separator())
    appMenu.addItem(NSMenuItem(title: "Services", action: nil, keyEquivalent: ""))
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)
    application.mainMenu = mainMenu

    let appState = AppState(isPreviewAppState: true)

    AppSettingsWindowPresenter.shared.installAppMenuItem(appState: appState)

    let settingsItem = appMenu.item(withTag: AppSettingsWindowPresenter.settingsMenuItemTag)
    XCTAssertEqual(appItem.title, "Brain Unfog")
    XCTAssertEqual(settingsItem?.title, "설정...")
    XCTAssertEqual(settingsItem?.keyEquivalent, ",")
    XCTAssertEqual(settingsItem?.keyEquivalentModifierMask, [.command])
  }

  func testSettingsViewKeepsLongVaultPathsInsideWindowWidth() {
    let appState = AppState(isPreviewAppState: true)
    appState.obsidianVaultRootURL = URL(
      fileURLWithPath:
        "/Users/three/Library/Mobile Documents/iCloud~md~obsidian/Documents/Very Long Primary Obsidian Vault Name With Many Nested Words"
    )
    let hostingController = NSHostingController(
      rootView: AppSettingsView().environmentObject(appState)
    )
    let window = NSWindow(contentViewController: hostingController)
    window.setContentSize(NSSize(width: 640, height: 430))

    window.contentView?.layoutSubtreeIfNeeded()

    XCTAssertLessThanOrEqual(hostingController.view.fittingSize.width, 700)
  }
}
