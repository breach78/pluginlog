import Foundation

extension AppState {
  func exportPhase0RedLineBaseline() async {
    errorMessage = "Legacy Phase 0 diagnostics were removed with PLAN-004 cleanup."
  }

  func scheduleDebugPhase0AutoExportIfNeeded() {}
}
