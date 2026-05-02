import SwiftUI

extension MainWorkspaceView {
  @ViewBuilder
  func content(visibleProjects: [UUID], isSearchPanelVisible: Bool) -> some View {
    if !appState.boardsLoaded {
      VStack(spacing: 14) {
        Text("Workspace is paused")
          .font(.title2.bold())
        Text("초기 렌더링 부하를 줄이기 위해 보드/타임라인은 필요할 때만 로드합니다.")
          .foregroundStyle(.secondary)
        Button("Load Workspace") {
          appState.loadWorkspaceBoardsIfNeeded()
        }
        .buttonStyle(.borderedProminent)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .simultaneousGesture(
        TapGesture().onEnded {
          dismissWorkspaceSearchPanel()
        })
    } else {
      let availableViewModes = appState.availableViewModes
      ZStack {
        ForEach(availableViewModes) { mode in
          if chromeState.shouldRenderBoard(currentMode: appState.viewMode, candidateMode: mode) {
            workspaceBoard(
              for: mode,
              visibleProjects: visibleProjects,
              isSearchPanelVisible: isSearchPanelVisible
            )
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .opacity(appState.viewMode == mode ? 1 : 0)
              .allowsHitTesting(appState.viewMode == mode)
              .zIndex(appState.viewMode == mode ? 1 : 0)
          }
        }
      }
      .simultaneousGesture(
        TapGesture().onEnded {
          dismissWorkspaceSearchPanel()
        })
    }
  }

  @ViewBuilder
  func workspaceBoard(
    for mode: ViewMode,
    visibleProjects: [UUID],
    isSearchPanelVisible: Bool
  ) -> some View {
    let isActive = appState.viewMode == mode
    let timelineSelectionProjectIDs = timelineProjectIDs(from: visibleProjects)
    let scheduleQuickAddProjectIDs = workspaceQuickAddProjectIDs

    switch mode {
    case .timeline:
      TimelineBoardView(
        projectListSortMode: Binding(
          get: { timelineProjectListSortMode },
          set: { timelineProjectListSortMode = $0 }
        ),
        hiddenProjectIDs: $hiddenTimelineProjectIDs,
        showsHiddenProjects: timelineShowsHiddenProjectLists,
        projectIDs: timelineSelectionProjectIDs,
        showsProjectPassthroughFrames: false,
        isActive: isActive,
        isInteractionObscured: isSearchPanelVisible,
        selectedProjectID: appState.selectedProjectID,
        onSelectProject: { projectID in
          selectProjectContext(projectID)
        },
        onToggleProjectSelection: { projectID in
          presentInspector(for: projectID)
        },
        onEditTask: { target in
          showTimelineTaskEditor(target)
        },
        onTaskDeleted: { projectID, taskID in
          handleTimelineTaskDeleted(projectID: projectID, taskID: taskID)
        }
      )
    case .schedule:
      ScheduleBoardView(
        projectIDs: timelineSelectionProjectIDs,
        quickAddProjectIDs: scheduleQuickAddProjectIDs,
        selectedProjectID: appState.selectedProjectID,
        onSelectProject: { projectID in
          presentInspector(for: projectID)
        },
        onTapEmptyArea: {
          dismissInspectorSelection()
        },
        isActive: isActive,
        onEditTask: { target in
          showTimelineTaskEditor(target)
        },
        onEditCalendarEvent: { event in
          showCalendarEventEditor(event)
        }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  func workspaceNavigationShellSection(snapshot: WorkspaceShellSnapshot) -> some View {
    workspaceDetailSection(snapshot: snapshot)
  }

  func workspaceDetailSection(snapshot: WorkspaceShellSnapshot) -> some View {
    HStack(spacing: 0) {
      workspaceMainPaneSection(snapshot: snapshot)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(2)

      workspaceInspectorReservationSection
    }
  }

  func workspaceMainPaneSection(snapshot: WorkspaceShellSnapshot) -> some View {
    workspaceSearchHostSection(snapshot: snapshot)
      .coordinateSpace(name: Self.mainPaneCoordinateSpaceName)
      .overlayPreferenceValue(WorkspaceViewModePickerFramePreferenceKey.self) { frame in
        if shouldDimNonInspectorUI {
          GeometryReader { _ in
            nonInspectorDimOverlay(
              visualExclusions: nonInspectorVisualExclusionRects(viewModePickerFrame: frame),
              passthroughRects: nonInspectorPassthroughRects(viewModePickerFrame: frame)
            )
            .allowsHitTesting(false)
          }
        }
      }
      .overlayPreferenceValue(TimelineTaskBadgeOverlayPresentationPreferenceKey.self) {
        presentation in
        timelineTaskBadgeOverlayHost(presentation)
      }
      .overlayPreferenceValue(TimelineDayHeaderOverlayPresentationPreferenceKey.self) {
        presentation in
        timelineDayHeaderOverlayHost(presentation)
      }
  }

  func workspaceSearchHostSection(snapshot: WorkspaceShellSnapshot) -> some View {
    workspaceMainPaneBaseSection(snapshot: snapshot)
      .overlayPreferenceValue(WorkspaceSearchFieldFramePreferenceKey.self) { frame in
        workspaceSearchResultsPanelHost(
          frame: frame,
          results: snapshot.searchResults,
          isVisible: snapshot.isSearchPanelVisible
        )
      }
  }

  func workspaceMainPaneBaseSection(snapshot: WorkspaceShellSnapshot) -> some View {
    VStack(spacing: 0) {
      workspaceChromeSection(snapshot: snapshot)
      workspaceModeDividerSection
      workspacePanelRouterSection(snapshot: snapshot)
    }
  }

  func workspaceChromeSection(snapshot: WorkspaceShellSnapshot) -> some View {
    header(
      searchResults: snapshot.searchResults,
      selectedSearchResult: snapshot.selectedSearchResult
    )
  }

  @ViewBuilder
  var workspaceModeDividerSection: some View {
    if appState.viewMode != .schedule {
      Divider()
    }
  }

  @ViewBuilder
  func workspacePanelRouterSection(snapshot: WorkspaceShellSnapshot) -> some View {
    content(
      visibleProjects: snapshot.filteredProjectIDs,
      isSearchPanelVisible: snapshot.isSearchPanelVisible
    )
  }

  var workspaceSidebarSection: some View {
    sidebar()
  }

  var workspaceInspectorReservationSection: some View {
    workspaceInspectorReservation(
      selection: inspectorSelection,
      taskEditTarget: activeWorkspaceTaskEditPanelTarget,
      calendarEventEditTarget: activeWorkspaceCalendarEventEditPanelTarget
    )
  }

  var workspaceOverlaySection: some View {
    workspaceInspectorOverlayHost(
      selection: inspectorSelection,
      taskEditTarget: activeWorkspaceTaskEditPanelTarget,
      calendarEventEditTarget: activeWorkspaceCalendarEventEditPanelTarget
    )
  }
}
