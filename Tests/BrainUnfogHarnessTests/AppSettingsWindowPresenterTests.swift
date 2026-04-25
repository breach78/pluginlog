import AppKit
import XCTest
@testable import BrainUnfogHarness

@MainActor
final class AppSettingsWindowPresenterTests: XCTestCase {
  func testInstallAppMenuItemAddsSettingsCommandToApplicationMenu() {
    let application = NSApplication.shared
    let previousMainMenu = application.mainMenu
    defer { application.mainMenu = previousMainMenu }

    let mainMenu = NSMenu()
    let appItem = NSMenuItem(title: "BrainUnfogHarness", action: nil, keyEquivalent: "")
    let appMenu = NSMenu(title: "BrainUnfogHarness")
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
}
