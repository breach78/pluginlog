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

      if let monthTitle = workspaceHeaderMonthTitle {
        Text(monthTitle)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .fixedSize(horizontal: true, vertical: false)
      }
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
      workspaceDisplayModeSelector
      workspaceQuickAddSection
      overdueRolloverButton

      if appState.viewMode == .timeline {
        todayJumpButton {
          showArchive = false
          appState.jumpTimelineToToday()
        }

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
        todayJumpButton {
          showArchive = false
          appState.jumpScheduleToToday()
        }
      }
    }
    .fixedSize(horizontal: true, vertical: false)
    .simultaneousGesture(
      TapGesture().onEnded {
        dismissWorkspaceSearchPanel()
      })
  }

  var workspaceDisplayModeSelector: some View {
    Picker("", selection: workspaceDisplayModeBinding) {
      ForEach(WorkspaceToolbarDisplayMode.allCases) { mode in
        Image(systemName: mode.systemImage)
          .help(mode.helpText)
          .accessibilityLabel(mode.accessibilityLabel)
          .tag(mode)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .frame(width: workspaceTitlebarModeSelectorWidth, height: workspaceTitlebarControlHeight)
    .help("보기 전환")
    .background {
      GeometryReader { proxy in
        Color.clear.preference(
          key: WorkspaceViewModePickerFramePreferenceKey.self,
          value: proxy.frame(in: .named(Self.mainPaneCoordinateSpaceName))
        )
      }
    }
  }

  var dailyJournalButton: some View {
    Button {
      openDailyJournalWindow()
    } label: {
      workspaceToolbarIcon(systemName: "exclamationmark")
    }
    .buttonStyle(.plain)
    .help("저널 열기")
    .accessibilityLabel("저널 열기")
  }

  var workspaceDisplayMode: WorkspaceToolbarDisplayMode {
    if appState.viewMode == .timeline {
      return .timeline
    }
    return scheduleDisplayMode == .month ? .month : .week
  }

  var workspaceHeaderMonthTitle: String? {
    guard appState.viewMode == .schedule, scheduleDisplayMode == .month else { return nil }
    let date = appState.scheduleMonthDisplayedMonthStart ?? Date()
    let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month], from: date)
    return "\(components.year ?? 0)년 \(components.month ?? 1)월"
  }

  var workspaceDisplayModeBinding: Binding<WorkspaceToolbarDisplayMode> {
    Binding(
      get: { workspaceDisplayMode },
      set: { mode in
        switch mode {
        case .timeline:
          appState.selectViewMode(.timeline)
        case .week:
          scheduleDisplayMode = .week
          appState.selectViewMode(.schedule)
        case .month:
          scheduleDisplayMode = .month
          appState.selectViewMode(.schedule)
        }
      }
    )
  }

  @ViewBuilder
  var workspaceQuickAddSection: some View {
    syncStatusIndicator
  }

  var overdueRolloverButton: some View {
    Button {
      rollOverdueTasksToTodayAllDay()
    } label: {
      workspaceToolbarIcon(
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
    workspaceToolbarIcon(systemName: "plus", tintColor: syncIndicatorColor)
  }

  func workspaceToolbarIcon(
    systemName: String,
    isLoading: Bool = false,
    tintColor: Color? = nil,
    symbolOffsetX: CGFloat = 0
  ) -> some View {
    let iconColor = tintColor ?? Color.primary
    return ZStack {
      Color.clear

      if isLoading {
        ProgressView()
          .controlSize(.small)
          .scaleEffect(0.72)
          .tint(iconColor)
      } else {
        Image(systemName: systemName)
          .font(.system(size: workspaceTitlebarIconFontSize, weight: .semibold))
          .foregroundStyle(iconColor)
          .offset(x: symbolOffsetX)
      }
    }
    .frame(
      width: workspaceTitlebarIconButtonSize,
      height: workspaceTitlebarControlHeight,
      alignment: .center
    )
    .contentShape(Rectangle())
  }

  func todayJumpButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      workspaceToolbarIcon(systemName: "calendar")
    }
    .buttonStyle(.plain)
    .help("오늘로 이동")
    .accessibilityLabel("오늘로 이동")
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

  var workspaceTitlebarIconFontSize: CGFloat {
    14
  }

  var workspaceTitlebarModeSelectorWidth: CGFloat {
    104
  }

  var workspaceTitlebarZoomButtonWidth: CGFloat {
    42
  }
}

enum WorkspaceToolbarDisplayMode: String, CaseIterable, Identifiable {
  case timeline
  case week
  case month

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .timeline:
      return "chart.bar.xaxis"
    case .week:
      return "clock"
    case .month:
      return "square.grid.3x3"
    }
  }

  var helpText: String {
    switch self {
    case .timeline:
      return "타임라인 보기"
    case .week:
      return "주간 스케줄 보기"
    case .month:
      return "월간 스케줄 보기"
    }
  }

  var accessibilityLabel: String {
    helpText
  }
}
