import AppKit
import SwiftUI

final class BUFAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !AppRuntimeEnvironment.isRunningPreview else { return }
    PlatformUIFoundation.shared.windowManager.activateApp()
    PlatformUIFoundation.shared.windowManager.bringVisibleWindowsToFront(titled: "Brain Unfog")
  }
}

@main
struct BUFApplication: App {
  @NSApplicationDelegateAdaptor(BUFAppDelegate.self) private var appDelegate
  @StateObject private var appState = AppState()

  var body: some Scene {
    WindowGroup(id: "main") {
      RootSceneView()
        .environmentObject(appState)
        .navigationTitle("Brain Unfog")
        .task {
          guard !AppRuntimeEnvironment.isRunningPreview else { return }
          await appState.launch()
          appState.scheduleDebugPhase0AutoExportIfNeeded()
        }
    }
    .commands {
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
}
