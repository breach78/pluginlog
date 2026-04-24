import SwiftUI

extension MainWorkspaceView {
  @ViewBuilder
  func content(visibleProjects: [UUID]) -> some View {
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
            workspaceBoard(for: mode, visibleProjects: visibleProjects)
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
  func workspaceBoard(for mode: ViewMode, visibleProjects: [UUID]) -> some View {
    let isActive = appState.viewMode == mode
    let timelineSelectionProjectIDs = timelineProjectIDs(from: visibleProjects)

    switch mode {
    case .compass:
      EmptyView()
    case .journal:
      EmptyView()
    case .timeline:
      TimelineBoardView(
        projectListSortMode: Binding(
          get: { projectListSortMode },
          set: { projectListSortMode = $0 }
        ),
        projectIDs: timelineSelectionProjectIDs,
        showsProjectPassthroughFrames: false,
        isActive: isActive,
        selectedProjectID: appState.selectedProjectID,
        onSelectProject: { projectID in
          presentInspector(for: projectID)
        },
        onToggleProjectSelection: { projectID in
          presentInspector(for: projectID)
        }
      )
    case .schedule:
      ScheduleBoardView(
        projectIDs: timelineSelectionProjectIDs,
        selectedProjectID: appState.selectedProjectID,
        onSelectProject: { projectID in
          presentInspector(for: projectID)
        },
        onTapEmptyArea: {
          dismissInspectorSelection()
        },
        isActive: isActive
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  func workspaceNavigationShellSection(snapshot: WorkspaceShellSnapshot) -> some View {
    NavigationSplitView(columnVisibility: .constant(.detailOnly)) {
      workspaceSidebarSection
    } detail: {
      workspaceDetailSection(snapshot: snapshot)
    }
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
    content(visibleProjects: snapshot.filteredProjectIDs)
  }

  var workspaceSidebarSection: some View {
    sidebar()
  }

  var workspaceInspectorReservationSection: some View {
    workspaceInspectorReservation(selection: inspectorSelection)
  }

  var workspaceOverlaySection: some View {
    workspaceInspectorOverlayHost(selection: inspectorSelection)
  }
}
