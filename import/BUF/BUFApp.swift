import AppKit
import SwiftUI

@MainActor
final class BUFAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !AppRuntimeEnvironment.isRunningPreview else { return }
    PlatformUIFoundation.shared.windowManager.activateApp()
    NSApp.mainMenu?.items.first?.title = "Brain Unfog"
    installSettingsMenuCommand()
    PlatformUIFoundation.shared.windowManager.bringVisibleWindowsToFront(titled: "Brain Unfog")
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    guard !AppRuntimeEnvironment.isRunningPreview else { return }
    installSettingsMenuCommand()
  }

  private func installSettingsMenuCommand() {
    AppSettingsWindowPresenter.shared.installAppMenuItem()
    Task { @MainActor in
      for delay in [100, 500, 1_500, 3_000] {
        try? await Task.sleep(for: .milliseconds(delay))
        AppSettingsWindowPresenter.shared.installAppMenuItem()
      }
    }
  }
}

@main
struct BUFApplication: App {
  @NSApplicationDelegateAdaptor(BUFAppDelegate.self) private var appDelegate
  @StateObject private var appState: AppState

  init() {
    let appState = AppState()
    _appState = StateObject(wrappedValue: appState)
    AppSettingsWindowPresenter.shared.register(appState: appState)
    Task { @MainActor in
      guard !AppRuntimeEnvironment.isRunningPreview else { return }
      await appState.launch()
      AppSettingsWindowPresenter.shared.installAppMenuItem(appState: appState)
      appState.scheduleDebugPhase0AutoExportIfNeeded()
    }
  }

  var body: some Scene {
    WindowGroup("Brain Unfog", id: "main") {
      RootSceneView()
        .environmentObject(appState)
        .task {
          guard !AppRuntimeEnvironment.isRunningPreview else { return }
          installSettingsMenuCommand()
        }
    }
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(after: .appInfo) {
        Button("설정...") {
          AppSettingsWindowPresenter.shared.show(appState: appState)
        }
        .keyboardShortcut(",", modifiers: .command)
      }

      CommandMenu("보기") {
        Button("타임라인") {
          appState.handleViewMenuSelection(.timeline)
        }
        .keyboardShortcut("1", modifiers: .command)

        Button("스케줄") {
          appState.handleViewMenuSelection(.schedule)
        }
        .keyboardShortcut("2", modifiers: .command)

      }

      CommandGroup(after: .textEditing) {
        Button("전체 검색으로 이동") {
          appState.handleWorkspaceSearchMenuCommand()
        }
        .keyboardShortcut("f", modifiers: .command)
      }

#if DEBUG
      CommandMenu("진단") {
        Button("Phase 0 기준선 내보내기") {
          Task { @MainActor in
            await appState.exportPhase0RedLineBaseline()
          }
        }
        .keyboardShortcut("0", modifiers: [.command, .option, .shift])
      }
#endif
    }
  }

  private func installSettingsMenuCommand() {
    AppSettingsWindowPresenter.shared.installAppMenuItem(appState: appState)
    Task { @MainActor in
      for delay in [250, 1_000, 2_500] {
        try? await Task.sleep(for: .milliseconds(delay))
        AppSettingsWindowPresenter.shared.installAppMenuItem(appState: appState)
      }
    }
  }
}
