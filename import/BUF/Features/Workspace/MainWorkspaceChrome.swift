import AppKit
import SwiftUI

extension MainWorkspaceView {
  func header(
    searchResults: [WorkspaceSearchResult],
    selectedSearchResult: WorkspaceSearchResult?
  ) -> some View {
    HStack(spacing: 10) {
      headerLeadingControls
        .layoutPriority(2)

      workspaceSearchField(
        searchResults: searchResults,
        selectedSearchResult: selectedSearchResult
      )
        .layoutPriority(0)

      Spacer()
    }
    .padding(12)
    .zIndex(4)
  }

  @ViewBuilder
  var headerLeadingControls: some View {
    let availableViewModes = appState.availableViewModes
    HStack(spacing: 6) {
      Picker("", selection: viewModeBinding) {
        ForEach(availableViewModes) { mode in
          Image(systemName: mode.iconName)
            .accessibilityLabel(mode.accessibilityTitle)
            .tag(mode)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: CGFloat(availableViewModes.count) * 36)
      .background {
        GeometryReader { proxy in
          Color.clear.preference(
            key: WorkspaceViewModePickerFramePreferenceKey.self,
            value: proxy.frame(in: .named(Self.mainPaneCoordinateSpaceName))
          )
        }
      }

      workspaceQuickAddSection

      if appState.viewMode == .timeline {
        Button("오늘") {
          showArchive = false
          appState.jumpTimelineToToday()
        }
        .buttonStyle(.bordered)

        HStack(spacing: 4) {
          Button("-") {
            appState.zoomOutTimelineDayColumn()
          }
          .buttonStyle(.bordered)
          .disabled(!appState.canZoomOutTimelineDayColumn())

          Button("+") {
            appState.zoomInTimelineDayColumn()
          }
          .buttonStyle(.bordered)
          .disabled(!appState.canZoomInTimelineDayColumn())
        }
      } else if appState.viewMode == .schedule {
        Button("오늘") {
          showArchive = false
          appState.jumpScheduleToToday()
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(.leading, -6)
    .fixedSize(horizontal: true, vertical: false)
    .simultaneousGesture(
      TapGesture().onEnded {
        dismissWorkspaceSearchPanel()
      })
  }

  @ViewBuilder
  var workspaceQuickAddSection: some View {
    syncStatusIndicator
  }

  var syncStatusIndicator: some View {
    syncStatusIndicatorButton
      .popover(isPresented: $chromeState.showSyncQuickAddPopover, arrowEdge: .bottom) {
        WorkspaceQuickAddPopoverContent(
          projects: syncQuickAddProjects,
          defaultProjectID: syncQuickAddProjectID,
          onSubmit: { title, projectID in
            createSyncQuickAddTask(title, projectID: projectID)
          },
          onCancel: {
            dismissSyncQuickAddPopover()
          }
        )
        .overlaySurface(
          cornerRadius: 12,
          strokeColor: .primary,
          style: workspacePresentationCardStyle
        )
      }
      .help("\(appState.reminderStatusDisplayText)\n오늘 올데이 할일 빠른 추가")
  }

  var syncStatusIndicatorButton: some View {
    Button {
      toggleSyncQuickAddPopover()
    } label: {
      syncStatusIndicatorLabel
    }
    .buttonStyle(.plain)
  }

  var syncStatusIndicatorLabel: some View {
    ZStack {
      Color.clear

      ZStack {
        Circle()
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))

        Image(systemName: "plus")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(syncIndicatorColor)
      }
      .frame(width: 18, height: 18)
      .overlay {
        Circle()
          .stroke(syncIndicatorColor, lineWidth: 1.5)
      }
      .offset(x: -7)
    }
    .frame(
      width: 24,
      height: 28,
      alignment: .center
    )
    .contentShape(Rectangle())
  }

  var syncIndicatorColor: Color {
    if appState.isReminderStatusRefreshing || appState.isReminderStatusReady {
      return .green
    }
    let status = appState.syncStatus.lowercased()
    if appState.hasInitialSyncConsent && (status == "idle" || status.hasPrefix("starting refresh")) {
      return .green
    }
    return .red
  }
}
