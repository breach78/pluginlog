import AppKit
import SwiftUI

struct ScheduleQuickAddProjectOption: Identifiable, Hashable {
  let id: UUID
  let title: String
}

enum ScheduleQuickAddFailureReason: String {
  case noAvailableProject = "quick_add_no_available_project"
  case requestedProjectUnavailable = "quick_add_requested_project_unavailable"
  case noVisibleDay = "quick_add_no_visible_day"

  var userMessage: String {
    switch self {
    case .noAvailableProject:
      return "Schedule quick add를 위한 기본 프로젝트를 찾지 못했습니다."
    case .requestedProjectUnavailable:
      return "선택한 프로젝트를 일정 quick add에서 찾지 못했습니다."
    case .noVisibleDay:
      return "현재 보이는 날짜가 없어 quick add 위치를 계산하지 못했습니다."
    }
  }
}

enum ScheduleInvalidDropReason: String {
  case externalPreviewUnavailable = "external_preview_unavailable"
  case payloadProviderMissing = "payload_provider_missing"
  case payloadDecodeFailed = "payload_decode_failed"
  case projectionUnavailable = "projection_unavailable"
}

enum ScheduleUserDefaultsKey {
  static let dateBoundarySnappingEnabled = "schedule.dateBoundarySnappingEnabled"
}

enum ScheduleCalendarFailureContext: String {
  case applyPreview = "apply_preview"
  case deleteEvent = "delete_event"
  case restoreDeletedEvent = "restore_deleted_event"
  case redeleteRestoredEvent = "redelete_restored_event"
}

enum ScheduleWorkspaceLoadFallback: Equatable {
  case queryEngineUnavailable
  case partialFailure(failedProjects: Int, totalProjects: Int)

  var notice: ScheduleBoardRuntimeNotice {
    switch self {
    case .queryEngineUnavailable:
      return ScheduleBoardRuntimeNotice(
        id: "workspace_query_engine_unavailable",
        symbol: "tray.full",
        title: "워크스페이스 일정 fallback",
        message: "워크스페이스 쿼리 엔진이 아직 준비되지 않아 워크스페이스 프로젝트 일정은 잠시 숨겨집니다."
      )
    case .partialFailure(let failedProjects, let totalProjects):
      return ScheduleBoardRuntimeNotice(
        id: "workspace_partial_failure_\(failedProjects)_\(totalProjects)",
        symbol: "exclamationmark.triangle",
        title: "워크스페이스 일정 일부 누락",
        message: "\(failedProjects)/\(totalProjects)개 프로젝트 스냅샷 로드에 실패해 일부 일정만 표시합니다."
      )
    }
  }
}

enum ScheduleViewportSyncDiagnostic: String, Equatable {
  case scrollRequestQueuedWithoutViewport = "scroll_request_queued_without_viewport"
  case dragProjectionFrameUnavailable = "drag_projection_frame_unavailable"

  var notice: ScheduleBoardRuntimeNotice? {
    switch self {
    case .scrollRequestQueuedWithoutViewport:
      return ScheduleBoardRuntimeNotice(
        id: rawValue,
        symbol: "arrow.left.arrow.right.circle",
        title: "Viewport sync 대기 중",
        message: "스크롤 뷰가 아직 준비되지 않아 점프 요청을 큐에 보관했습니다."
      )
    case .dragProjectionFrameUnavailable:
      return nil
    }
  }
}

struct ScheduleBoardRuntimeNotice: Identifiable, Equatable {
  let id: String
  let symbol: String
  let title: String
  let message: String
}

enum ScheduleResizeEdge: Hashable {
  case start
  case end
}

struct ScheduleTaskDragState {
  let entryID: String
  let taskID: UUID
  let isPreparationSlot: Bool
  let targetCompletedWorkUnits: Int?
  let originalDay: Date
  let originalTimeMinutes: Int?
  let originalDurationMinutes: Int?
  let originalViewportFrame: CGRect
  let originalPointerViewportX: CGFloat
  let originalPointerViewportY: CGFloat
  let originalPointerScheduleY: CGFloat
  let originalTopScheduleY: CGFloat
  var translation: CGSize = .zero
  var currentPointerViewportLocation: CGPoint?
  var isInAllDayZone: Bool = false
}

struct CommittedTaskDropState {
  let originalFrame: CGRect
  let isOriginalAllDay: Bool
  let dropFrame: CGRect
  let color: Color
  let isAllDay: Bool
  let label: String?
}

struct ScheduleCalendarDragState {
  let eventID: String
  let originalDay: Date
  let originalTimeMinutes: Int?
  let originalDurationMinutes: Int?
  let originalViewportFrame: CGRect
  let originalPointerViewportX: CGFloat
  let originalPointerViewportY: CGFloat
  let originalPointerScheduleY: CGFloat
  let originalTopScheduleY: CGFloat
  var translation: CGSize = .zero
  var currentPointerViewportLocation: CGPoint?
  var isInAllDayZone: Bool = false
}

struct ScheduleTaskResizeState {
  let entryID: String
  let taskID: UUID
  let isPreparationSlot: Bool
  let targetCompletedWorkUnits: Int?
  let originalDay: Date
  let visibleDay: Date
  let originalTimeMinutes: Int
  let originalDurationMinutes: Int
  let edge: ScheduleResizeEdge
  let originalViewportFrame: CGRect
  let xOffsetWithinDay: CGFloat
  let originalPointerScheduleY: CGFloat
  let originalEdgeScheduleY: CGFloat
  var translationHeight: CGFloat = 0
  var currentPointerViewportLocation: CGPoint?
}

struct ScheduleCalendarResizeState {
  let eventID: String
  let originalDay: Date
  let visibleDay: Date
  let originalTimeMinutes: Int
  let originalDurationMinutes: Int
  let edge: ScheduleResizeEdge
  let originalViewportFrame: CGRect
  let xOffsetWithinDay: CGFloat
  let originalPointerScheduleY: CGFloat
  let originalEdgeScheduleY: CGFloat
  var translationHeight: CGFloat = 0
  var currentPointerViewportLocation: CGPoint?
}

struct ScheduleTimedQuickCreateSelection: Equatable {
  let dayIndex: Int
  let day: Date
  let startMinutes: Int
  let durationMinutes: Int
}

struct PendingScheduleCalendarEditAction: Identifiable {
  let id = UUID()
  let eventID: String
  let preview: ScheduleInteractionPreview
  let actionName: String
}

struct ScheduleTaskSnapshotCache {
  let sourceSignature: Int
  let taskDescriptors: [WorkspaceScheduleTaskDescriptor]
  let workspaceTasksByID: [UUID: WorkspaceScheduleTaskDescriptor]
  let signature: Int
}

struct OptimisticScheduleTaskScheduleState: Equatable, Hashable {
  let day: Date?
  let timeMinutes: Int?
  let durationMinutes: Int?
}
