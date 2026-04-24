# ARTIFACT-002: PLAN-004 Phase 0 deletion inventory

## Status

Inventory only. No files or runtime data have been deleted.

## User decisions applied

- Keep only the lightweight Logseq/Reminders/Calendar bridge plus Schedule and Timeline.
- Delete attachment code and `.buf/attachments` contents.
- Do not migrate old `.buf` SQLite domain data.
- Replace oversized legacy dependencies with smaller retained concepts before deletion.

## Runtime data deletion inventory

No `.buf/attachments` directory was found under the current repository workspace.

Before runtime data deletion, resolve the active Logseq graph path and report exact paths:

- `<active-logseq-graph>/.buf/attachments`
- `<active-logseq-graph>/.buf/attachments/projects`
- `<active-logseq-graph>/.buf/attachments/tasks`
- `<active-logseq-graph>/.buf/attachments/archive`
- Old `.buf` SQLite domain database paths discovered under `<active-logseq-graph>/.buf`

Gate:

- Stop before deleting these paths.
- Delete only after the exact resolved paths are shown to the user.

## Replacement-required before deletion

These files are deletion targets, but deleting them now would break Schedule, Timeline, or sync. Build retained replacements first.

Calendar bridge replacement:

- `import/BUF/App/AppStateOwnedCalendarSync.swift`
- `import/BUF/Services/OwnedScheduleCalendarInvalidationPolicy.swift`
- `import/BUF/Services/OwnedScheduleCalendarSupport.swift`
- `import/BUF/Services/OwnedScheduleCalendarSyncPolicy.swift`

Retained projection replacement:

- `import/BUF/App/AppStateRuntimeProjectionPatch.swift`
- `import/BUF/App/AppStateRuntimeProjectionRead.swift`
- `import/BUF/App/AppStateScheduleProjectionRead.swift`
- `import/BUF/Services/ReminderRuntimeProjectionReadModelService.swift`
- `import/BUF/Services/ScheduleProjectionService.swift`
- `import/BUF/Services/TimelineProjectionService.swift`
- `import/BUF/Services/WorkspaceTreeRepository.swift`
- `import/BUF/Persistence/NormalizedPersistence.swift`
- `import/BUF/Persistence/NormalizedWorkspaceOverlayMerge.swift`
- `import/BUF/Persistence/RuntimeSidecarSQLiteBootstrap.swift`

Project/task command replacement:

- `import/BUF/Services/ProjectLifecycleService.swift`
- `import/BUF/Services/ProjectOrdering.swift`
- `import/BUF/Services/TaskOrdering.swift`
- `import/BUF/Services/BoardService.swift`
- `import/BUF/Services/SequentialTaskService.swift`

Outliner source replacement:

- `import/BUF/App/AppStateOutliner.swift`
- `import/BUF/App/AppStateOutlinerReminderSource.swift`
- `import/BUF/App/OutlinerReminderSyncCoordinator.swift`
- `import/BUF/Features/Outliner/OutlineNodeRowAccessoryBand.swift`
- `import/BUF/Features/Outliner/OutlineNodeRowDisplay.swift`
- `import/BUF/Features/Outliner/OutlineRowLayoutSpec.swift`
- `import/BUF/Features/Outliner/OutlinerFoundation.swift`
- `import/BUF/Features/Outliner/OutlinerInlineEditors.swift`
- `import/BUF/Features/Outliner/OutlinerIntegratedStore.swift`
- `import/BUF/Features/Outliner/OutlinerInteractionOperations.swift`
- `import/BUF/Features/Outliner/OutlinerLiveSync.swift`
- `import/BUF/Features/Outliner/OutlinerModels.swift`
- `import/BUF/Features/Outliner/OutlinerNodeRowViews.swift`
- `import/BUF/Features/Outliner/OutlinerReminderSync.swift`
- `import/BUF/Features/Outliner/OutlinerRowActionHandler.swift`
- `import/BUF/Features/Outliner/OutlinerSelectionState.swift`
- `import/BUF/Features/Outliner/OutlinerSessionSnapshot.swift`
- `import/BUF/Features/Outliner/OutlinerView.swift`
- `import/BUF/Features/Outliner/OutlinerViewOperations.swift`
- `import/BUF/Features/Outliner/OutlinerViewSync.swift`
- `import/BUF/Features/Outliner/OutlinerViewportState.swift`
- `import/BUF/Features/Outliner/OutlinerWindowController.swift`
- `import/BUF/Features/Outliner/ProjectDocumentStore.swift`
- `import/BUF/Features/Outliner/ProjectRootStructureSidecar.swift`
- `import/BUF/Features/Outliner/ReminderProjectionBootstrapSeedService.swift`
- `import/BUF/Features/Outliner/ReminderProjectionSidecarMutationService.swift`
- `import/BUF/Features/Outliner/TaskMirrorPlacementStore.swift`

## UI/source deletion targets after references are removed

Project Detail:

- `import/BUF/Features/ProjectWindow/DetachedProjectWindowController.swift`
- `import/BUF/Features/ProjectWindow/NoteDocument.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailAttachments.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailBlockPageLoadPolicy.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailBlockPageModels.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailBlockPageQueryService.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailBlockPageStateStore.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailHeaderSection.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailHostStatusView.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailHostView.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailNoteSection.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailOutlinerView.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailSelectionDiagnostics.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailSharedTypes.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailTaskListPerformanceRecorder.swift`
- `import/BUF/Features/ProjectWindow/ProjectDetailTaskSection.swift`
- `import/BUF/Features/ProjectWindow/ProjectNoteAttachmentEmbedding.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskDragCoordinator.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskEditorSession.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskListAnimationCoordinator.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskListContainerView.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskListLayoutEngine.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskLocalReorderSession.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskMeasurementCache.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskReorderInteractionMode.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskRetainedListLayout.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskRetainedListReadOnlyView.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskRetainedListShell.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskRetainedListTypes.swift`
- `import/BUF/Features/ProjectWindow/ProjectTaskRowView.swift`
- `import/BUF/Features/ProjectWindow/ProjectWindowDropSupport.swift`
- `import/BUF/Features/ProjectWindow/ProjectWindowEditOrchestrator.swift`
- `import/BUF/Features/ProjectWindow/ProjectWindowMarkdownSupport.swift`

Journal and Obsidian:

- `import/BUF/Features/Journal/JournalBoardChrome.swift`
- `import/BUF/Features/Journal/JournalBoardDaySection.swift`
- `import/BUF/Features/Journal/JournalBoardSummaryPipeline.swift`
- `import/BUF/Features/Journal/JournalBoardSupport.swift`
- `import/BUF/Features/Journal/JournalBoardTextSystem.swift`
- `import/BUF/Features/Journal/JournalBoardView.swift`
- `import/BUF/Services/ObsidianJournalStore.swift`
- `import/BUF/Services/ObsidianProjectNoteStore.swift`

Compass and AI services:

- `import/BUF/Features/Compass/CompassBoardScreen.swift`
- `import/BUF/Features/Compass/CompassBoardView.swift`
- `import/BUF/Models/CompassModels.swift`
- `import/BUF/Models/CompassRecommendationModels.swift`
- `import/BUF/Services/CompassActionService.swift`
- `import/BUF/Services/CompassBoardRuntimeService.swift`
- `import/BUF/Services/CompassBootstrapService.swift`
- `import/BUF/Services/CompassDeltaUpdateService.swift`
- `import/BUF/Services/CompassGenerationSafeguards.swift`
- `import/BUF/Services/CompassModelConfigurationStore.swift`
- `import/BUF/Services/CompassModelStore.swift`
- `import/BUF/Services/CompassRebuildEstimateService.swift`
- `import/BUF/Services/CompassRecommendationService.swift`
- `import/BUF/Services/CompassRunMonitor.swift`
- `import/BUF/Services/CompassSafetyService.swift`
- `import/BUF/Services/CompassSeedImportService.swift`
- `import/BUF/Services/CompassSeedPackageLoader.swift`
- `import/BUF/Services/GeminiAPIKeyStore.swift`
- `import/BUF/Services/GeminiCompassService.swift`
- `import/BUF/Services/GeminiGenerateContentSummaryService.swift`
- `import/BUF/Services/OpenAIAPIKeyStore.swift`
- `import/BUF/Services/OpenAIResponsesSummaryService.swift`
- `import/BUF/Features/Settings/OpenAISettingsView.swift`
- `import/BUF/Features/Settings/OpenAISettingsWindowController.swift`

Archive:

- `import/BUF/Features/Archive/ArchiveView.swift`
- `import/BUF/Services/ArchiveService.swift`
- `import/BUF/Services/ArchivedProjectBundleStore.swift`

Attachments and external documents:

- `import/BUF/Models/AttachmentEntity.swift`
- `import/BUF/Services/AttachmentStore.swift`
- `import/BUF/Services/DocumentReferenceSystem.swift`

History and undo:

- `import/BUF/Models/ProjectHistoryEvent.swift`
- `import/BUF/Services/ProjectHistoryService.swift`
- `import/BUF/Services/TaskDeletionUndoSupport.swift`
- `import/BUF/Services/UndoCoordinator.swift`

Legacy SwiftData/domain models:

- `import/BUF/Models/Project.swift`
- `import/BUF/Models/SyncMetadata.swift`
- `import/BUF/Models/TaskItem.swift`
- `import/BUF/Models/TaskProjectClonePlacement.swift`
- `import/BUF/Models/OutlinerCoreStorage.swift`
- `import/BUF/Persistence/DataStack.swift`
- `import/BUF/Persistence/OutlinerCoreStorageCoordinator.swift`

## Edit-only retained files

These files contain retained app wiring and should not be deleted as files. Remove only legacy branches from them.

- `import/BUF/App/AppState.swift`
- `import/BUF/App/AppStateCalendarOwnerCommands.swift`
- `import/BUF/App/AppStateCalendarServiceRegistry.swift`
- `import/BUF/App/AppStateDiagnostics.swift`
- `import/BUF/App/AppStateEditorState.swift`
- `import/BUF/App/AppStateLaunchAndSetup.swift`
- `import/BUF/App/AppStateProjectActions.swift`
- `import/BUF/App/AppStateProjectCommandDispatch.swift`
- `import/BUF/App/AppStateReminderOwnerCommands.swift`
- `import/BUF/App/AppStateSidecarOwnerCommands.swift`
- `import/BUF/App/AppStateSourceIO.swift`
- `import/BUF/App/AppStateSyncAndPersistence.swift`
- `import/BUF/App/AppStateWorkspaceUI.swift`
- `import/BUF/App/RootSceneView.swift`
- `import/BUF/App/WorkspaceNavigation.swift`
- `import/BUF/BUFApp.swift`
- `import/BUF/Persistence/ContainerPaths.swift`
- `import/BUF/Persistence/StorageCoordinator.swift`
- `import/BUF/Services/ProjectIdentityResolver.swift`
- `import/BUF/Services/ReminderProjectionSidecarReadService.swift`
- `import/BUF/Services/ScheduleCalendarStore.swift`
- `import/BUF/Features/Workspace/MainWorkspaceActions.swift`
- `import/BUF/Features/Workspace/MainWorkspaceChrome.swift`
- `import/BUF/Features/Workspace/MainWorkspaceOverlays.swift`
- `import/BUF/Features/Workspace/MainWorkspacePanels.swift`
- `import/BUF/Features/Workspace/MainWorkspaceSearch.swift`
- `import/BUF/Features/Workspace/MainWorkspaceSidebar.swift`
- `import/BUF/Features/Workspace/MainWorkspaceView.swift`

## Hold files

These are retained product files and must stay unless a later task packet replaces them.

- `import/BUF/Features/Schedule/ScheduleBoardActions.swift`
- `import/BUF/Features/Schedule/ScheduleBoardAllDayRail.swift`
- `import/BUF/Features/Schedule/ScheduleBoardChrome.swift`
- `import/BUF/Features/Schedule/ScheduleBoardTimeGrid.swift`
- `import/BUF/Features/Schedule/ScheduleBoardView.swift`
- `import/BUF/Features/Schedule/ScheduleEventModel.swift`
- `import/BUF/Features/Schedule/ScheduleEventStores.swift`
- `import/BUF/Features/Schedule/ScheduleInteractionLayers.swift`
- `import/BUF/Features/Timeline/TimelineBoardActions.swift`
- `import/BUF/Features/Timeline/TimelineBoardOverlays.swift`
- `import/BUF/Features/Timeline/TimelineBoardRefresh.swift`
- `import/BUF/Features/Timeline/TimelineBoardRows.swift`
- `import/BUF/Features/Timeline/TimelineBoardSupport.swift`
- `import/BUF/Features/Timeline/TimelineBoardView.swift`
- `import/BUF/Services/LogseqPageFilenameCodec.swift`
- `import/BUF/Services/LogseqProjectPageStore.swift`
- `import/BUF/Services/LogseqReminderPropertyCodec.swift`
- `import/BUF/Services/ManagedLogseqSyncHardening.swift`
- `import/BUF/Services/ReminderGateway.swift`
- `import/BUF/Services/ReminderRecurrenceCodec.swift`
- `import/BUF/Services/ReminderSourceObserver.swift`
- `import/BUF/Utilities/LogseqDeepLinking.swift`
- `import/BUF/Utilities/ReminderNoteCodec.swift`

## Next execution slice

Start with non-destructive rewiring:

- Remove visible Project Detail and Outliner entry points.
- Route project selection to Logseq page open.
- Remove visible Journal/Compass/Archive/AI settings entry points.
- Keep legacy runtime files until retained projection and calendar bridge are implemented.
