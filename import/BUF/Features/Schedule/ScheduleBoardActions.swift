import AppKit
import SwiftUI

extension ScheduleBoardView {
  var allowsScheduleDragDateSnapping: Bool {
    false
  }

  func allowScheduleMutation(_ feature: String) -> Bool {
    appState.errorMessage = RetainedSurfaceMutationGate.block(.schedule, feature: feature)
    return false
  }

  func allowScheduleRetainedWrite(_ feature: String) -> Bool {
    _ = feature
    return true
  }

  func recordWorkspaceLoadFallback(_ fallback: ScheduleWorkspaceLoadFallback?) {
    if workspaceLoadFallback != fallback {
      workspaceLoadFallback = fallback
    }
  }

  func recordScheduleViewportDiagnostic(_ diagnostic: ScheduleViewportSyncDiagnostic) {
    guard viewportSyncDiagnostic != diagnostic else { return }
    viewportSyncDiagnostic = diagnostic
    AppLogger.ui.error(
      "schedule viewport diagnostic [\(diagnostic.rawValue, privacy: .public)]"
    )
  }

  func clearScheduleViewportDiagnostic(_ diagnostic: ScheduleViewportSyncDiagnostic? = nil) {
    guard let current = viewportSyncDiagnostic else { return }
    guard diagnostic == nil || current == diagnostic else { return }
    viewportSyncDiagnostic = nil
  }

  func handleScheduleCalendarEditError(
    _ error: ScheduleCalendarEditError,
    context: ScheduleCalendarFailureContext
  ) {
    AppLogger.ui.error(
      "schedule calendar failure [\(context.rawValue, privacy: .public)]: \(error.localizedDescription, privacy: .public)"
    )
    calendarEditError = error
  }

  func handleScheduleCalendarEditFailure(
    _ error: Error,
    context: ScheduleCalendarFailureContext,
    fallback: ScheduleCalendarEditError
  ) {
    AppLogger.ui.error(
      "schedule calendar failure [\(context.rawValue, privacy: .public)]: \(error.localizedDescription, privacy: .public)"
    )
    calendarEditError = fallback
  }

  func logScheduleInvalidDrop(at location: CGPoint, reason: ScheduleInvalidDropReason) {
    AppLogger.ui.error(
      "schedule invalid drop [\(reason.rawValue, privacy: .public)] at x=\(location.x, privacy: .public) y=\(location.y, privacy: .public)"
    )
    if reason == .projectionUnavailable {
      recordScheduleViewportDiagnostic(.dragProjectionFrameUnavailable)
    }
  }

  func scheduleWorkspaceLoadSignature(
    projectIDs: [UUID],
    workspaceTreeRevision: Int
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(projectIDs.map(\.uuidString).sorted())
    hasher.combine(workspaceTreeRevision)
    return hasher.finalize()
  }
}
