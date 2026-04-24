import Foundation
import SwiftData
import SwiftUI

#if DEBUG
private struct PreviewWorkspaceData {
  let modelContainer: ModelContainer
  let runtimeSnapshot: OutlineProjectionRuntimeSnapshot
  let defaultProjectID: UUID
}

@MainActor
private func makePreviewWorkspaceData() -> PreviewWorkspaceData {
  let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
  let modelContainer = try! ModelContainer(
    for: AttachmentEntity.self,
    ProjectHistoryEvent.self,
    configurations: configuration
  )

  let mainProjectID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  let sideProjectID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
  let now = Date()

  let mainNodes = [
    OutlineNode(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
      canonicalID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
      text: "디자인 리허설 마무리",
      type: .task(completed: false),
      reminderIdentifier: "preview-main-1",
      reminderExternalIdentifier: "preview-main-1"
    ),
    OutlineNode(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
      canonicalID: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
      text: "요약 노트 작성",
      type: .task(completed: false),
      reminderIdentifier: "preview-main-2",
      reminderExternalIdentifier: "preview-main-2"
    ),
  ]
  let sideNodes = [
    OutlineNode(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
      canonicalID: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
      text: "다음 주 일정 등록",
      type: .task(completed: false),
      reminderIdentifier: "preview-side-1",
      reminderExternalIdentifier: "preview-side-1"
    )
  ]

  let runtimeSnapshot = OutlineProjectionRuntimeSnapshot(
    projects: [
      OutlinerProject(
        id: mainProjectID,
        title: "메인 프로젝트",
        document: OutlineDocument(rootNodes: mainNodes)
      ),
      OutlinerProject(
        id: sideProjectID,
        title: "사이드 프로젝트",
        document: OutlineDocument(rootNodes: sideNodes)
      ),
    ],
    currentProjectID: mainProjectID,
    featureSidecarByReminderIdentifier: [:],
    featureSidecarByNodeID: [:],
    reminderMetadataByReminderIdentifier: [
      "preview-main-1": ReminderMetadataSnapshot(
        dueDate: Calendar.current.date(byAdding: .day, value: 1, to: now),
        hasExplicitTime: false,
        priority: 1
      ),
      "preview-main-2": ReminderMetadataSnapshot(
        dueDate: Calendar.current.date(byAdding: .day, value: 2, to: now),
        hasExplicitTime: false,
        priority: 0
      ),
      "preview-side-1": ReminderMetadataSnapshot(
        dueDate: Calendar.current.date(byAdding: .day, value: 3, to: now),
        hasExplicitTime: false,
        priority: 0
      ),
    ],
    reminderMetadataByNodeID: [:],
    projectReminderListIdentifierByProjectID: [
      mainProjectID: "preview-workspace-1",
      sideProjectID: "preview-workspace-2",
    ],
    projectReminderListExternalIdentifierByProjectID: [
      mainProjectID: "preview-workspace-1",
      sideProjectID: "preview-workspace-2",
    ],
    projectColorHexByProjectID: [
      mainProjectID: "#0A84FF",
      sideProjectID: "#34C759",
    ],
    reminderModifiedAtByReminderExternalIdentifier: [
      "preview-main-1": now,
      "preview-main-2": now,
      "preview-side-1": now,
    ],
    workspaceStructureRecord: ReminderWorkspaceStructureRecord(
      orderedReminderListExternalIdentifiers: ["preview-workspace-1", "preview-workspace-2"],
      createdAt: now,
      updatedAt: now
    ),
    projectTaskOrderByReminderListExternalIdentifier: [
      "preview-workspace-1": ReminderProjectTaskOrderRecord(
        reminderListExternalIdentifier: "preview-workspace-1",
        orderedTopLevelReminderExternalIdentifiers: ["preview-main-1", "preview-main-2"],
        createdAt: now,
        updatedAt: now
      ),
      "preview-workspace-2": ReminderProjectTaskOrderRecord(
        reminderListExternalIdentifier: "preview-workspace-2",
        orderedTopLevelReminderExternalIdentifiers: ["preview-side-1"],
        createdAt: now,
        updatedAt: now
      ),
    ],
    projectRootStructureByReminderListExternalIdentifier: [:],
    projectFeatureSidecarByProjectID: [
      mainProjectID: ReminderProjectFeatureSidecarRecord(
        reminderListExternalIdentifier: "preview-workspace-1",
        projectNoteMarkdown: "프리뷰용 샘플 프로젝트입니다.",
        localStartDate: nil,
        localDeadline: nil,
        progressStageRaw: ProjectProgressStage.do.storageRawValue,
        boardOrder: 0,
        attachmentManifestRaw: "",
        createdAt: now,
        updatedAt: now
      ),
      sideProjectID: ReminderProjectFeatureSidecarRecord(
        reminderListExternalIdentifier: "preview-workspace-2",
        projectNoteMarkdown: "짧은 할 일이 들어간 샘플 프로젝트입니다.",
        localStartDate: nil,
        localDeadline: nil,
        progressStageRaw: ProjectProgressStage.decide.storageRawValue,
        boardOrder: 1,
        attachmentManifestRaw: "",
        createdAt: now,
        updatedAt: now
      ),
    ],
    projectFeatureSidecarByReminderListExternalIdentifier: [
      "preview-workspace-1": ReminderProjectFeatureSidecarRecord(
        reminderListExternalIdentifier: "preview-workspace-1",
        projectNoteMarkdown: "프리뷰용 샘플 프로젝트입니다.",
        localStartDate: nil,
        localDeadline: nil,
        progressStageRaw: ProjectProgressStage.do.storageRawValue,
        boardOrder: 0,
        attachmentManifestRaw: "",
        createdAt: now,
        updatedAt: now
      ),
      "preview-workspace-2": ReminderProjectFeatureSidecarRecord(
        reminderListExternalIdentifier: "preview-workspace-2",
        projectNoteMarkdown: "짧은 할 일이 들어간 샘플 프로젝트입니다.",
        localStartDate: nil,
        localDeadline: nil,
        progressStageRaw: ProjectProgressStage.decide.storageRawValue,
        boardOrder: 1,
        attachmentManifestRaw: "",
        createdAt: now,
        updatedAt: now
      ),
    ],
    taskFeatureSidecarByReminderExternalIdentifier: [:],
    taskSourceRuntimeStateByReminderExternalIdentifier: [:],
    projectionEngine: .appSidecar
  )

  return PreviewWorkspaceData(
    modelContainer: modelContainer,
    runtimeSnapshot: runtimeSnapshot,
    defaultProjectID: mainProjectID
  )
}

@MainActor
private func makePreviewAppState(with data: PreviewWorkspaceData) -> AppState {
  let appState = AppState(isPreviewAppState: true)
  appState.modelContainer = data.modelContainer
  appState.installCachedRuntimeProjectionSnapshot(data.runtimeSnapshot)
  appState.isOutlinerProjectionBootstrapPending = false
  appState.isLaunching = false
  appState.boardsLoaded = true
  appState.hasInitialSyncConsent = true
  appState.hasSyncConsentDecision = true
  appState.syncStatus = "Preview"
  appState.isPrivateObsidianFeaturesEnabled = false
  appState.viewMode = .timeline
  appState.selectedProjectID = data.defaultProjectID
  appState.loadWorkspaceBoardsIfNeeded()
  return appState
}

#Preview("Main Workspace") {
  let previewData = makePreviewWorkspaceData()
  MainWorkspaceView()
    .environmentObject(makePreviewAppState(with: previewData))
    .modelContainer(previewData.modelContainer)
    .frame(minWidth: 1200, minHeight: 760)
}

#Preview("Quick Add Popover") {
  let projects = [
    WorkspaceQuickAddProjectOption(id: UUID(), title: "메인 프로젝트"),
    WorkspaceQuickAddProjectOption(id: UUID(), title: "사이드 프로젝트"),
  ]

  return WorkspaceQuickAddPopoverContent(
    projects: projects,
    defaultProjectID: projects.first?.id,
    onSubmit: { _, _ in },
    onCancel: {}
  )
  .padding()
  .frame(width: 300)
}

#Preview("Project Detail Host") {
  let previewData = makePreviewWorkspaceData()
  ProjectDetailHostView(
    projectID: previewData.defaultProjectID,
    fixedWidth: nil,
    showsLeadingDivider: false,
    registersWorkspaceEscapeHandler: false
  )
  .environmentObject(makePreviewAppState(with: previewData))
  .modelContainer(previewData.modelContainer)
  .frame(minWidth: 980, minHeight: 760)
}
#endif
