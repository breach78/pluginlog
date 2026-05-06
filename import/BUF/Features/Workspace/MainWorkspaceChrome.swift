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
    .padding(.leading, workspaceTitlebarControlInset)
    .padding(.trailing, 12)
    .padding(.vertical, 12)
    .zIndex(4)
  }

  @ViewBuilder
  var headerLeadingControls: some View {
    HStack(spacing: workspaceTitlebarControlSpacing) {
      dailyJournalButton
      viewModeToggleButton

      workspaceQuickAddSection
      overdueRolloverButton

      if appState.viewMode == .timeline {
        Button("오늘") {
          showArchive = false
          appState.jumpTimelineToToday()
        }
        .buttonStyle(.bordered)
        .frame(width: workspaceTitlebarTodayButtonWidth, height: workspaceTitlebarControlHeight)

        Button("-") {
          appState.zoomOutTimelineDayColumn()
        }
        .buttonStyle(.bordered)
        .frame(width: workspaceTitlebarZoomButtonWidth, height: workspaceTitlebarControlHeight)
        .disabled(!appState.canZoomOutTimelineDayColumn())

        Button("+") {
          appState.zoomInTimelineDayColumn()
        }
        .buttonStyle(.bordered)
        .frame(width: workspaceTitlebarZoomButtonWidth, height: workspaceTitlebarControlHeight)
        .disabled(!appState.canZoomInTimelineDayColumn())
      } else if appState.viewMode == .schedule {
        Button("오늘") {
          showArchive = false
          appState.jumpScheduleToToday()
        }
        .buttonStyle(.bordered)
        .frame(width: workspaceTitlebarTodayButtonWidth, height: workspaceTitlebarControlHeight)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
    .simultaneousGesture(
      TapGesture().onEnded {
        dismissWorkspaceSearchPanel()
      })
  }

  @ViewBuilder
  var viewModeToggleButton: some View {
    if let targetMode = nextViewMode {
      Button {
        appState.selectViewMode(targetMode)
      } label: {
        Image(systemName: targetMode.iconName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(
            width: workspaceTitlebarIconButtonSize,
            height: workspaceTitlebarControlHeight
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("\(targetMode.accessibilityTitle) 보기로 전환")
      .accessibilityLabel("\(targetMode.accessibilityTitle) 보기로 전환")
      .background {
        GeometryReader { proxy in
          Color.clear.preference(
            key: WorkspaceViewModePickerFramePreferenceKey.self,
            value: proxy.frame(in: .named(Self.mainPaneCoordinateSpaceName))
          )
        }
      }
    }
  }

  var dailyJournalButton: some View {
    Button {
      openDailyJournalWindow()
    } label: {
      Image(systemName: "exclamationmark")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.primary)
        .frame(
          width: workspaceTitlebarIconButtonSize,
          height: workspaceTitlebarControlHeight
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("저널 열기")
    .accessibilityLabel("저널 열기")
  }

  var nextViewMode: ViewMode? {
    let availableViewModes = appState.availableViewModes
    guard
      availableViewModes.count > 1,
      let currentIndex = availableViewModes.firstIndex(of: appState.viewMode)
    else {
      return availableViewModes.first { $0 != appState.viewMode }
    }
    return availableViewModes[(currentIndex + 1) % availableViewModes.count]
  }

  @ViewBuilder
  var workspaceQuickAddSection: some View {
    syncStatusIndicator
  }

  var overdueRolloverButton: some View {
    Button {
      rollOverdueTasksToTodayAllDay()
    } label: {
      roundWorkspaceToolbarIcon(
        systemName: "arrow.right.to.line",
        isLoading: isRollingOverdueTasksToToday,
        tintColor: .accentColor,
        symbolOffsetX: -3
      )
    }
    .buttonStyle(.plain)
    .disabled(isRollingOverdueTasksToToday)
    .help("오늘 이전 미완료 할일을 오늘 올데이로 이동")
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
    roundWorkspaceToolbarIcon(systemName: "plus")
  }

  func roundWorkspaceToolbarIcon(
    systemName: String,
    isLoading: Bool = false,
    tintColor: Color? = nil,
    symbolOffsetX: CGFloat = 0
  ) -> some View {
    let iconColor = tintColor ?? syncIndicatorColor
    return ZStack {
      Color.clear

      ZStack {
        Circle()
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))

        if isLoading {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(0.7)
            .tint(iconColor)
        } else {
          Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(iconColor)
            .offset(x: symbolOffsetX)
        }
      }
      .frame(width: 18, height: 18)
      .overlay {
        Circle()
          .stroke(iconColor, lineWidth: 1.5)
      }
    }
    .frame(
      width: workspaceTitlebarIconButtonSize,
      height: workspaceTitlebarControlHeight,
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

  var workspaceTitlebarControlInset: CGFloat {
    134
  }

  var workspaceTitlebarControlSpacing: CGFloat {
    10
  }

  var workspaceTitlebarIconButtonSize: CGFloat {
    30
  }

  var workspaceTitlebarControlHeight: CGFloat {
    30
  }

  var workspaceTitlebarTodayButtonWidth: CGFloat {
    58
  }

  var workspaceTitlebarZoomButtonWidth: CGFloat {
    42
  }
}
