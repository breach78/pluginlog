# FEATURE-CLEANUP-CHECKLIST-001: Current app feature tree

## Purpose

이 문서는 현재 `import/BUF` 앱 기능을 삭제 선택용 체크박스 트리로 정리한다.

사용법:

- 체크박스는 "삭제 후보로 선택"이라는 뜻이다.
- 체크한 뒤 이 파일을 저장하고 알려주면, 선택된 항목을 기준으로 삭제 Task Packet을 만든다.
- `risk: schema`, `risk: sync`, `risk: data` 항목은 바로 삭제하지 않고 마이그레이션/fixture gate를 먼저 만든다.
- 현재 retained 목표는 `Logseq + Reminders + Schedule + Timeline`이다. 이 축은 기본적으로 체크하지 않는다.
- 이 트리는 삭제 순서가 아니라 기능 의존성 지도다. 실제 삭제 순서는 별도 Task Packet에서 다시 정한다.

## Feature Tree

- [ ] App shell and launch
  - [ ] macOS app lifecycle and main window
    - Files: `import/BUF/BUFApp.swift`, `import/BUF/App/RootSceneView.swift`
    - Risk: app boot
  - [ ] View menu: Timeline and Schedule commands
    - Files: `import/BUF/BUFApp.swift`, `import/BUF/App/AppStateWorkspaceUI.swift`
    - Risk: retained
  - [ ] Settings window
    - Files: `import/BUF/Features/Settings/OpenAISettingsView.swift`, `OpenAISettingsWindowController.swift`
    - Risk: low if no retained diagnostics/settings needed
  - [x] Note font menu
    - Files: `import/BUF/BUFApp.swift`, typography-related settings
    - Risk: low
  - [ ] Debug diagnostics menu and Phase 0 export
    - Files: `import/BUF/BUFApp.swift`, `import/BUF/App/AppStateDiagnostics.swift`
    - Risk: diagnostics

- [ ] First-run setup and local storage
  - [ ] Logseq graph folder picker
    - Files: `import/BUF/Features/Setup/SetupContainerView.swift`, `import/BUF/App/AppStateLaunchAndSetup.swift`
    - Risk: retained
  - [ ] Graph-local `.buf` app container
    - Files: `import/BUF/Persistence/StorageCoordinator.swift`, `ContainerPaths.swift`, `AppContainer.swift`
    - Risk: retained, data
  - [ ] Reminders and Calendar permission status/actions
    - Files: `SetupContainerView.swift`, `ScheduleCalendarStore.swift`, `ReminderGateway.swift`
    - Risk: retained, sync
  - [ ] Security-scoped bookmarks for graph/container
    - Files: `AppStateLaunchAndSetup.swift`, `StorageCoordinator.swift`
    - Risk: data access
  - [ ] Container health and structure validation
    - Files: `StorageCoordinator.swift`, `ContainerHealth` usage
    - Risk: data

- [ ] Logseq integration
  - [ ] Logseq page filename codec
    - Files: `import/BUF/Services/LogseqPageFilenameCodec.swift`
    - Risk: retained
  - [ ] Logseq page store under `pages`
    - Files: `import/BUF/Services/LogseqProjectPageStore.swift`
    - Risk: retained, sync
  - [ ] Managed task section round-trip
    - Files: `LogseqProjectPageStore.swift`, `LogseqReminderPropertyCodec.swift`
    - Risk: retained, sync
  - [ ] Project page deep-link opening
    - Files: `import/BUF/Utilities/LogseqDeepLinking.swift`, `MainWorkspaceView.swift`
    - Risk: retained
  - [ ] Logseq identity hardening
    - Files: `import/BUF/Services/ManagedLogseqSyncHardening.swift`
    - Risk: retained, sync

- [ ] Reminders sync
  - [ ] EventKit Reminders gateway
    - Files: `import/BUF/Services/ReminderGateway.swift`
    - Risk: retained, sync
  - [ ] Reminder list equals project/page
    - Files: `AppStateReminderOwnerCommands.swift`, `ProjectIdentityResolver.swift`, `ReminderProjectionSidecarReadService.swift`
    - Risk: retained, sync
  - [ ] Reminder item equals Logseq task
    - Files: `AppStateOutlinerReminderSource.swift`, `OutlinerReminderSyncCoordinator.swift`
    - Risk: retained, sync
  - [ ] Task metadata: `date::`, `duration::`, `repeat::`
    - Files: `LogseqReminderPropertyCodec.swift`, `ReminderNoteCodec.swift`, `ReminderRecurrenceCodec.swift`
    - Risk: retained, sync
  - [ ] Identity metadata: `brain_unfog_task_id::`, `reminder_external_id::`
    - Files: `ManagedLogseqSyncHardening.swift`, `ReminderTaskAdoptionPolicy.swift`
    - Risk: retained, sync
  - [ ] Remote source observer and invalidation
    - Files: `ReminderSourceObserver.swift`, `AppStateSyncAndPersistence.swift`
    - Risk: retained, sync
  - [ ] Conflict/fail-closed policy
    - Files: `ReminderConflictPolicy.swift`, `ReminderSyncHardening.swift`
    - Risk: retained, sync
  - [ ] Sync edit gate and recovery journal
    - Files: `ReminderSyncHardening.swift`, `AppStateLaunchAndSetup.swift`
    - Risk: retained, sync

- [ ] Calendar integration
  - [ ] Foreign calendar read-only overlay
    - Files: `ScheduleCalendarStore.swift`, `ScheduleEventStores.swift`, `ScheduleBoardView.swift`
    - Risk: retained
  - [x] BUF-owned calendar creation and writes
    - Files: `OwnedScheduleCalendarSupport.swift`, `OwnedScheduleCalendarSyncPolicy.swift`, `AppStateOwnedCalendarSync.swift`
    - Risk: retained, sync
  - [ ] `calendar_event_external_id::` round-trip
    - Files: `LogseqProjectPageStore.swift`, `OwnedScheduleCalendarSyncPolicy.swift`
    - Risk: retained, sync
  - [ ] Calendar permission prompt-once policy
    - Files: `ScheduleCalendarStore.swift`, `ScheduleCalendarAccessPromptPolicyTests.swift`
    - Risk: retained
  - [ ] Owned event invalidation observer
    - Files: `OwnedScheduleCalendarInvalidationPolicy.swift`, `AppStateCalendarOwnerCommands.swift`
    - Risk: retained, sync

- [ ] Main workspace shell
  - [ ] Workspace chrome and view mode picker
    - Files: `MainWorkspaceView.swift`, `MainWorkspaceChrome.swift`, `WorkspaceChromeState.swift`
    - Risk: retained
  - [ ] Sidebar project list
    - Files: `MainWorkspaceSidebar.swift`, `WorkspaceProjectTaskDropSupport.swift`
    - Risk: retained if project navigation remains
  - [ ] Workspace global search
    - Files: `MainWorkspaceSearch.swift`, `WorkspaceSearchService.swift`, `WorkspaceSearchProjectionService.swift`
    - Risk: medium
  - [ ] Quick add task from workspace chrome
    - Files: `MainWorkspaceChrome.swift`, `MainWorkspaceActions.swift`
    - Risk: medium, sync
  - [ ] Project sort/reorder controls
    - Files: `MainWorkspaceView.swift`, `ProjectOrdering.swift`, `TaskOrdering.swift`
    - Risk: medium, sync
  - [ ] Project selection routing to Logseq page or embedded detail
    - Files: `MainWorkspaceView.swift`, `WorkspaceNavigation.swift`
    - Risk: retained if Logseq page opening remains
  - [ ] Embedded inspector/detail overlay
    - Files: `MainWorkspaceOverlays.swift`, `ProjectDetailHostView.swift`
    - Risk: high, currently still reachable

- [ ] Timeline view
  - [ ] Timeline board rendering
    - Files: `TimelineBoardView.swift`, `TimelineBoardRows.swift`, `TimelineProjectionService.swift`
    - Risk: retained
  - [ ] Project bars and day columns
    - Files: `TimelineBoardSupport.swift`, `TimelineBoardRows.swift`
    - Risk: retained
  - [ ] Timeline project selection
    - Files: `TimelineBoardView.swift`, `MainWorkspacePanels.swift`
    - Risk: retained
  - [ ] Timeline task completion
    - Files: `TimelineBoardActions.swift`, `AppStateProjectActions.swift`
    - Risk: retained, sync
  - [ ] Timeline task schedule/planned-work edits
    - Files: `TimelineBoardActions.swift`, `TaskItem.swift`
    - Risk: retained, sync
  - [ ] Timeline drag/drop and ordering
    - Files: `TimelineProjectDropSupport.swift`, `TimelineBoardActions.swift`
    - Risk: medium, sync
  - [ ] Timeline project color/stage controls
    - Files: `TimelineBoardRows.swift`, `TimelineBoardActions.swift`
    - Risk: medium
  - [ ] Timeline undo registration
    - Files: `TimelineBoardActions.swift`, `UndoCoordinator.swift`
    - Risk: high, behavior

- [ ] Schedule view
  - [ ] Schedule board rendering
    - Files: `ScheduleBoardView.swift`, `ScheduleBoardChrome.swift`, `ScheduleProjectionService.swift`
    - Risk: retained
  - [ ] All-day rail
    - Files: `ScheduleBoardAllDayRail.swift`
    - Risk: retained
  - [ ] Timed grid
    - Files: `ScheduleBoardTimeGrid.swift`, `ScheduleDayTimelineLayoutEngine.swift`
    - Risk: retained
  - [ ] Schedule task quick add
    - Files: `ScheduleBoardView.swift`, `ScheduleBoardActions.swift`
    - Risk: medium, sync
  - [ ] Task drag/resize/postpone
    - Files: `ScheduleInteractionLayers.swift`, `ScheduleBoardActions.swift`
    - Risk: retained, sync
  - [ ] Calendar event display/edit/delete/reveal UI
    - Files: `ScheduleBoardTimeGrid.swift`, `ScheduleCalendarStore.swift`
    - Risk: retained for overlay, high for writable owned events
  - [ ] Schedule undo registration
    - Files: `ScheduleBoardActions.swift`, `UndoCoordinator.swift`
    - Risk: high, behavior

- [x] Project detail and retained task list
  - [x] Embedded project detail host
    - Files: `ProjectDetailHostView.swift`, `MainWorkspaceOverlays.swift`
    - Risk: high, currently reachable
  - [x] Detached project window
    - Files: `DetachedProjectWindowController.swift`, `AppStateWorkspaceUI.swift`
    - Risk: medium
  - [x] Project note editor/markdown snapshot
    - Files: `ProjectDetailNoteSection.swift`, `ProjectWindowMarkdownSupport.swift`
    - Risk: high if Logseq owns notes
  - [x] Project task list UI
    - Files: `ProjectTaskListContainerView.swift`, `ProjectTaskRowView.swift`, `ProjectTaskRetainedListShell.swift`
    - Risk: high, may still support retained actions
  - [x] Project task drag/reorder/edit orchestration
    - Files: `ProjectTaskDragCoordinator.swift`, `ProjectWindowEditOrchestrator.swift`
    - Risk: high, sync
  - [x] Project detail attachment UI
    - Files: `ProjectDetailAttachments.swift`, `ProjectTaskRetainedListReadOnlyView.swift`
    - Risk: data, delete candidate after UI disconnect
  - [x] Project detail performance diagnostics
    - Files: `ProjectDetailTaskListPerformanceRecorder.swift`
    - Risk: low

- [x] Outliner subsystem
  - [x] Outliner window
    - Files: `AppStateOutliner.swift`, `OutlinerWindowController.swift`, `OutlinerView.swift`
    - Risk: high, source still compiled
  - [x] Outline node editing
    - Files: `OutlinerInlineEditors.swift`, `OutlinerInteractionOperations.swift`
    - Risk: high
  - [x] Outline tree rendering and virtualization
    - Files: `OutlinerFoundation.swift`, `OutlinerNodeRowViews.swift`
    - Risk: high
  - [x] Outliner live sync
    - Files: `OutlinerLiveSync.swift`, `OutlinerViewSync.swift`
    - Risk: sync
  - [x] Outliner reminder projection
    - Files: `OutlinerReminderSync.swift`, `ReminderProjectionBootstrapSeedService.swift`, `ReminderProjectionSidecarMutationService.swift`
    - Risk: retained dependency possible
  - [x] Project document store
    - Files: `ProjectDocumentStore.swift`, `ProjectRootStructureSidecar.swift`
    - Risk: retained dependency possible
  - [x] Task mirror placement
    - Files: `TaskMirrorPlacementStore.swift`, `TaskProjectClonePlacement.swift`
    - Risk: data

- [x] Attachment and external document subsystem
  - [x] Attachment SwiftData model
    - Files: `Models/AttachmentEntity.swift`, `Persistence/DataStack.swift`
    - Risk: schema, data
  - [x] Local attachment store and file repository
    - Files: `Services/AttachmentStore.swift`, `Persistence/ContainerPaths.swift`
    - Risk: data
  - [x] Attachment import/open/reveal/delete/move commands
    - Files: `AppStateProjectActions.swift`, `ProjectDetailAttachments.swift`
    - Risk: data
  - [x] Attachment directories under `.buf`
    - Paths: `.buf/attachments`, `.buf/attachments/projects`, `.buf/attachments/tasks`, `.buf/attachments/archive`
    - Risk: data, filesystem
  - [x] Thumbnail/cache attachment index
    - Files: `AttachmentStore.swift`, `AppStateDiagnostics.swift`
    - Risk: data
  - [x] External document reference system
    - Files: `DocumentReferenceSystem.swift`, `NormalizedPersistence.swift`
    - Risk: data, may be separate from attachments

- [x] Journal subsystem
  - [x] Journal board UI
    - Files: `Features/Journal/JournalBoardView.swift`, `JournalBoardChrome.swift`, `JournalBoardDaySection.swift`
    - Risk: hidden UI, delete candidate after reference removal
  - [x] Journal markdown editor/text rendering
    - Files: `JournalBoardTextSystem.swift`
    - Risk: hidden UI
  - [x] Obsidian journal store
    - Files: `Services/ObsidianJournalStore.swift`, `AppStateSourceIO.swift`
    - Risk: data
  - [x] Journal summary pipeline
    - Files: `JournalBoardSummaryPipeline.swift`
    - Risk: AI, data
  - [x] Local/Gemini summary services for Journal
    - Files: `JournalBoardSummaryPipeline.swift`, `GeminiGenerateContentSummaryService.swift`
    - Risk: AI
  - [x] Journal notifications/source hooks
    - Files: `AppNotifications.swift`, `AppStateSourceIO.swift`
    - Risk: hidden dependency

- [x] Compass subsystem
  - [x] Compass board UI
    - Files: `Features/Compass/CompassBoardScreen.swift`, `CompassBoardView.swift`
    - Risk: hidden UI
  - [x] Compass recommendation engine
    - Files: `CompassRecommendationService.swift`, `CompassBoardRuntimeService.swift`, `CompassActionService.swift`
    - Risk: AI, history dependency
  - [x] Compass bootstrap/delta/rebuild flows
    - Files: `CompassBootstrapService.swift`, `CompassDeltaUpdateService.swift`, `CompassRebuildEstimateService.swift`
    - Risk: AI, data
  - [x] Compass self-model/config stores
    - Files: `CompassModelStore.swift`, `CompassModelConfigurationStore.swift`, `CompassModels.swift`
    - Risk: data
  - [x] Compass seed import/package loader
    - Files: `CompassSeedImportService.swift`, `CompassSeedPackageLoader.swift`
    - Risk: data
  - [x] Gemini Compass service and safeguards
    - Files: `GeminiCompassService.swift`, `CompassGenerationSafeguards.swift`, `CompassSafetyService.swift`
    - Risk: AI

- [x] Obsidian legacy integration
  - [x] Obsidian project note store
    - Files: `Services/ObsidianProjectNoteStore.swift`, `AppStateSourceIO.swift`
    - Risk: data
  - [x] Obsidian folder bookmark/defaults
    - Files: `AppState.swift`, `AppStateLaunchAndSetup.swift`
    - Risk: persisted defaults
  - [x] Private Obsidian feature flag
    - Files: `Models/Enums.swift`, `AppStateWorkspaceUI.swift`, `AppState.swift`
    - Risk: low after callers removed

- [x] Archive subsystem
  - [x] Archive view UI
    - Files: `Features/Archive/ArchiveView.swift`
    - Risk: hidden UI
  - [x] Archive service marker
    - Files: `Services/ArchiveService.swift`
    - Risk: low
  - [x] Archived project bundle store
    - Files: `Services/ArchivedProjectBundleStore.swift`, `AppStateProjectActions.swift`
    - Risk: data
  - [x] Soft-delete/archive project semantics
    - Files: `Project.swift`, `AppStateProjectActions.swift`, `WorkspaceTreeRepository.swift`
    - Risk: behavior, sync

- [x] History and undo
  - [x] Project history SwiftData model
    - Files: `Models/ProjectHistoryEvent.swift`, `Persistence/DataStack.swift`
    - Risk: schema, data
  - [x] Project history service
    - Files: `Services/ProjectHistoryService.swift`, `AppStateProjectActions.swift`
    - Risk: behavior, Compass dependency
  - [x] Undo coordinator
    - Files: `Services/UndoCoordinator.swift`, `AppState.swift`
    - Risk: behavior
  - [x] Task deletion undo snapshots
    - Files: `Services/TaskDeletionUndoSupport.swift`, `AppStateProjectActions.swift`
    - Risk: behavior, sync
  - [x] Timeline undo registrations
    - Files: `TimelineBoardActions.swift`
    - Risk: behavior
  - [x] Schedule undo registrations
    - Files: `ScheduleBoardActions.swift`
    - Risk: behavior
  - [x] Workspace/sidebar undo registrations
    - Files: `MainWorkspaceActions.swift`
    - Risk: behavior

- [x] AI and API keys
  - [x] OpenAI API key storage
    - Files: `OpenAIAPIKeyStore.swift`, `OpenAISettingsView.swift`
    - Risk: low if no AI retained
  - [x] OpenAI summary service
    - Files: `OpenAIResponsesSummaryService.swift`
    - Risk: AI
  - [x] Gemini API key storage
    - Files: `GeminiAPIKeyStore.swift`, `AppStateWorkspaceUI.swift`
    - Risk: low if Compass/Journal removed
  - [x] Gemini summary/generation services
    - Files: `GeminiGenerateContentSummaryService.swift`, `GeminiCompassService.swift`
    - Risk: AI
  - [x] API key status refresh
    - Files: `AppStateWorkspaceUI.swift`, `OpenAISettingsView.swift`
    - Risk: low

- [x] Persistence and derived read models
  - [x] SwiftData app stack
    - Files: `Persistence/DataStack.swift`, `Models/AttachmentEntity.swift`, `Models/ProjectHistoryEvent.swift`
    - Risk: schema, data
  - [x] Legacy SwiftData/domain model files
    - Files: `Models/Project.swift`, `Models/TaskItem.swift`, `Models/SyncMetadata.swift`
    - Risk: hidden compile dependency, schema if re-registered elsewhere
  - [x] Outliner core storage models
    - Files: `Models/OutlinerCoreStorage.swift`, `Persistence/OutlinerCoreStorageCoordinator.swift`
    - Risk: retained dependency possible
  - [x] Normalized SQLite persistence
    - Files: `Persistence/NormalizedPersistence.swift`, `RuntimeSidecarSQLiteBootstrap.swift`
    - Risk: retained, sync
  - [x] Workspace tree repository
    - Files: `Services/WorkspaceTreeRepository.swift`
    - Risk: retained dependency possible
  - [x] Runtime projection patch/read services
    - Files: `AppStateRuntimeProjectionPatch.swift`, `AppStateRuntimeProjectionRead.swift`
    - Risk: retained, sync
  - [x] Schedule/timeline read model services
    - Files: `ScheduleProjectionService.swift`, `TimelineProjectionService.swift`, `ReminderRuntimeProjectionReadModelService.swift`
    - Risk: retained
- [x] Project lifecycle/order/task order services
    - Files: `ProjectLifecycleService.swift`, `ProjectOrdering.swift`, `TaskOrdering.swift`
    - Risk: retained dependency possible
  - [x] Board/sequential task helper services
    - Files: `BoardService.swift`, `SequentialTaskService.swift`
    - Risk: hidden compile dependency

- [ ] Shared UI/platform utilities
  - [ ] Platform UI foundation
    - Files: `Utilities/PlatformUIFoundation.swift`
    - Risk: retained
  - [ ] Motion/overlay styling
    - Files: `MotionSystem.swift`, `MotionTransaction.swift`, `OverlaySurfaceStyle.swift`
    - Risk: retained UI
  - [ ] Drag payload codecs
    - Files: `DragPayloadCodec.swift`, `TaskDragPayload.swift`
    - Risk: retained for drag/drop
  - [ ] App logger and notifications
    - Files: `AppLogger.swift`, `AppNotifications.swift`
    - Risk: retained
  - [ ] Color codec
    - Files: `ColorHexCodec.swift`
    - Risk: retained

## High-confidence retained items

체크하지 않는 것을 권장한다:

- [ ] Logseq graph setup and `.buf` container
- [ ] Logseq page store and filename codec
- [ ] Reminders list/task sync
- [ ] Sync hardening/fail-closed identity policy
- [ ] BUF-owned calendar sync
- [ ] Foreign calendar read-only overlay
- [ ] Timeline view
- [ ] Schedule view
- [ ] Runtime projection/read model path used by Timeline and Schedule

## High-confidence deletion candidates

체크해도 비교적 삭제 방향이 명확하지만, 실제 삭제 전 build/test slice가 필요하다:

- [ ] Journal UI/source files
- [ ] Compass UI/source files
- [ ] Obsidian legacy bookmark/default UI and source-store paths
- [ ] OpenAI/Gemini settings if Journal/Compass are removed
- [ ] Archive view UI if archive semantics are retained only internally or removed separately
- [ ] Debug Phase 0 export if diagnostics are no longer needed

## Must be staged with migration

체크해도 바로 삭제하지 않는다:

- [ ] `AttachmentEntity` and attachment SwiftData schema
- [ ] `ProjectHistoryEvent` and history SwiftData schema
- [ ] `.buf/attachments` directory contents
- [ ] `.buf/data/main.sqlite` model migration
- [ ] `Models/Project.swift`, `Models/TaskItem.swift`, `Models/SyncMetadata.swift` if any current code path still references them
- [ ] Project detail task list if it still owns retained task edits
- [ ] Outliner projection if Timeline/Schedule still read from it
- [ ] Undo/redo if retained edit actions still depend on undo snapshots
- [ ] Archive semantics if current delete flow still expects restore/sidecar cleanup

## Current known blockers

- [ ] Calendar permission prompt behavior may still require app-bundle/TCC packaging outside SwiftPM runtime.
- [ ] Attachment and history models are registered in `DataStack`; schema removal needs migration.
- [ ] Project detail and Outliner code are still compiled and may feed retained runtime projections.
- [ ] Sync deletion behavior must remain fail-closed until deterministic fixture gates cover delete/repair paths.
