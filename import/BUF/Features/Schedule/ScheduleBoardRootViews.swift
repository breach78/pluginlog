import AppKit
import SwiftUI

extension ScheduleBoardView {
  @ViewBuilder
  var body: some View {
    switch displayMode {
    case .week:
      scheduleBoardRoot
    case .month:
      scheduleMonthRoot
    }
  }

  var scheduleMonthRoot: some View {
    let taskSnapshot = resolvedScheduleTaskSnapshot(
      preferCached: appState.isEditorMotionSuppressed || !isActive
    )
    let projection = appState.resolvedScheduleCalendarOverlayProjection()
    let rawMonthItemsSignature = ScheduleMonthItemCache.signature(
      taskSignature: taskSnapshot.signature,
      visibleEventsSignature: projection.visibleEventsSignature,
      calendar: calendar
    )
    let rawMonthItems = scheduleMonthItemCache.items(
      taskSnapshot: taskSnapshot,
      projection: projection,
      calendar: calendar
    )
    let monthItems = scheduleMonthItemsApplyingOptimisticTaskCompletion(rawMonthItems)
    let monthItemsSignature = scheduleMonthItemsSignature(
      baseSignature: rawMonthItemsSignature,
      items: rawMonthItems
    )

    return ScheduleMonthView(
      anchorDate: monthAnchorDateBinding,
      today: today,
      items: monthItems,
      itemsSignature: monthItemsSignature,
      selectedDate: selectedScheduleMonthDate,
      calendar: calendar,
      onSelectDay: { day, items in
        selectedScheduleMonthDate = day
        onShowMonthDetail(ScheduleMonthDetailPanelTarget(date: day, items: items))
      },
      onToggleTaskCompletion: { taskID, projectID, isCompleted in
        updateScheduleTaskCompletion(
          taskID: taskID,
          projectID: projectID,
          isCompleted: !isCompleted,
          completionDate: isCompleted ? nil : .now,
          registerUndo: true
        )
      },
      onMoveItem: { item, target in
        moveScheduleMonthItem(item, to: target)
      },
      externalDragTargetDate: externalMonthDragTargetDate,
      externalDayDropTarget: externalDayDropTarget,
      onDropTargetsChanged: onMonthDropTargetsChanged,
      scrollToTodayToken: appState.scheduleJumpToTodayToken
    )
    .onAppear {
      if scheduleMonthAnchorDate == nil {
        scheduleMonthAnchorDate = today
      }
      if isActive {
        refreshScheduledTaskSnapshotIfNeeded(force: true, snapshot: taskSnapshot)
        refreshCalendarOverlay(force: projection.accessDenied)
      }
    }
    .task(
      id: scheduleWorkspaceLoadSignature(
        projectIDs: activeProjectIDs,
        workspaceTreeRevision: appState.workspaceTreeRevision
      )
    ) {
      guard isActive else { return }
      await reloadWorkspaceScheduleProjectDetails(for: activeProjectIDs)
    }
    .onChange(of: monthAnchorDate) { _, _ in
      guard isActive, displayMode == .month else { return }
      refreshCalendarOverlay(force: true)
    }
    .onChange(of: appState.scheduleJumpToTodayToken) { _, _ in
      guard displayMode == .month else { return }
      scheduleMonthAnchorDate = today
    }
    .onChange(of: appState.scheduleJumpToDateToken) { _, _ in
      guard displayMode == .month else { return }
      scheduleMonthAnchorDate = appState.scheduleJumpTargetDate ?? today
    }
    .onChange(of: monthTaskSourceSignature) { _, _ in
      guard isActive, displayMode == .month, !appState.isEditorMotionSuppressed else { return }
      refreshScheduledTaskSnapshotIfNeeded(force: false, snapshot: taskSnapshot)
    }
    .onChange(of: appState.currentDayChangeToken) { _, _ in
      guard isActive, displayMode == .month else { return }
      refreshCalendarOverlay(force: true)
    }
    .onChange(of: isActive) { _, active in
      if active {
        Task {
          await reloadWorkspaceScheduleProjectDetails(for: activeProjectIDs)
        }
        refreshScheduledTaskSnapshotIfNeeded(force: false, snapshot: taskSnapshot)
        refreshCalendarOverlay(force: true)
      } else {
        calendarOverlayRefreshTask?.cancel()
        calendarOverlayRefreshTask = nil
      }
    }
    .onDisappear {
      calendarOverlayRefreshTask?.cancel()
      calendarOverlayRefreshTask = nil
    }
  }

  var monthTaskSourceSignature: Int {
    scheduleTaskSourceSignature
  }

  var scheduleBoardRoot: some View {
    let context = makeBodyContext()

    return GeometryReader { geometry in
      scheduleBoardViewportSection(geometry: geometry, context: context)
    }
    .confirmationDialog(
      "반복 일정 변경",
      isPresented: Binding(
        get: { pendingCalendarEditAction != nil },
        set: { isPresented in
          if !isPresented {
            pendingCalendarEditAction = nil
          }
        }
      ),
      titleVisibility: .visible
    ) {
      Button(ScheduleCalendarRecurringEditScope.thisEvent.title) {
        commitPendingCalendarEdit(scope: .thisEvent)
      }
      Button(ScheduleCalendarRecurringEditScope.futureEvents.title) {
        commitPendingCalendarEdit(scope: .futureEvents)
      }
      Button("취소", role: .cancel) {
        pendingCalendarEditAction = nil
      }
    } message: {
      Text("반복 이벤트라서 적용 범위를 선택해야 합니다.")
    }
    .alert(item: $calendarEditError) { error in
      Alert(
        title: Text("캘린더 일정 변경 실패"),
        message: Text(error.errorDescription ?? "일정 시간을 변경하지 못했습니다."),
        dismissButton: .default(Text("확인"))
      )
    }
    .background(scheduleBoardGeometryPreferenceSurface)
    .onDrop(
      of: [TaskDragPayload.textTypeIdentifier],
      delegate: ScheduleExternalTaskDropDelegate(
        resolveTarget: externalTaskDropTarget(at:),
        onPerformTaskDrop: applyExternalTaskDrop(taskID:target:),
        onInvalidDrop: logScheduleInvalidDrop(at:reason:)
      )
    )
    .onPreferenceChange(ScheduleBoardGlobalFramePreferenceKey.self) { frame in
      boardFrameInGlobal = frame
      if !frame.isNull, viewportSyncDiagnostic == .dragProjectionFrameUnavailable {
        viewportSyncDiagnostic = nil
      }
    }
    .onAppear {
      requestTodayScroll()
      syncScheduleBoardCaches(
        filteredEvents: context.filteredEvents,
        backgroundEvents: context.backgroundEvents,
        taskSnapshot: context.taskSnapshot,
        layoutCache: context.layoutCache,
        layoutSourceSignature: context.layoutSourceSignature,
        force: true
      )
      if isActive {
        refreshCalendarOverlay(force: scheduleCalendarOverlayProjection.accessDenied)
      }
    }
    .task(
      id: scheduleWorkspaceLoadSignature(
        projectIDs: activeProjectIDs,
        workspaceTreeRevision: appState.workspaceTreeRevision
      )
    ) {
      guard isActive else { return }
      await reloadWorkspaceScheduleProjectDetails(for: activeProjectIDs)
    }
    .onChange(of: appState.scheduleJumpToTodayToken) { _, _ in
      requestTodayScroll()
    }
    .onChange(of: appState.scheduleJumpToDateToken) { _, _ in
      requestScroll(to: appState.scheduleJumpTargetDate ?? .now)
    }
    .onChange(of: appState.isHoveringTimelineDayHeaderOverlay) { _, isHovering in
      if isHovering {
        scheduleDayHeaderDetachWorkItem?.cancel()
        scheduleDayHeaderDetachWorkItem = nil
      } else {
        dismissScheduleDayHeaderOverlayIfDetached()
      }
    }
    .onChange(of: appState.currentDayChangeToken) { _, _ in
      guard isActive else { return }
      syncScheduleBoardCaches(
        filteredEvents: context.filteredEvents,
        backgroundEvents: context.backgroundEvents,
        taskSnapshot: context.taskSnapshot,
        layoutCache: context.layoutCache,
        layoutSourceSignature: context.layoutSourceSignature,
        force: false
      )
      refreshCalendarOverlay(force: true)
    }
    .onChange(of: dayRange) { _, _ in
      guard isActive else { return }
      dismissScheduleDayHeaderHoverIfObscured()
      refreshCalendarOverlay()
    }
    .onChange(of: horizontalOffsetX) { _, _ in
      dismissScheduleDayHeaderHoverIfObscured()
      if scrollViewportState.scrollView != nil {
        clearScheduleViewportDiagnostic(.scrollRequestQueuedWithoutViewport)
      }
    }
    .onChange(of: verticalOffsetY) { _, _ in
      if scrollViewportState.scrollView != nil {
        clearScheduleViewportDiagnostic(.scrollRequestQueuedWithoutViewport)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .reminderAppEditingEscapePressed)) { _ in
      guard pendingTimedQuickCreateSelection != nil else { return }
      pendingTimedQuickCreateSelection = nil
      activeTimedQuickCreateSelection = nil
      cancelScheduleDayHeaderOverlay()
    }
    .onChange(of: context.liveTaskSourceSignature) { _, _ in
      guard isActive, !appState.isEditorMotionSuppressed else { return }
      refreshScheduledTaskSnapshotIfNeeded(force: false, snapshot: context.taskSnapshot)
      refreshScheduleDayHeaderSectionsIfNeeded(
        sourceSignature: refreshedScheduleDayHeaderSourceSignature(
          taskSignature: context.taskSnapshot.signature
        ),
        force: false
      )
    }
    .onChange(of: context.liveLayoutSourceSignature) { _, newSignature in
      guard isActive, !appState.isEditorMotionSuppressed else { return }
      refreshLayoutCacheIfNeeded(
        filteredEvents: context.filteredEvents,
        backgroundEvents: context.backgroundEvents,
        taskSnapshot: context.taskSnapshot,
        sourceSignature: newSignature,
        force: false,
        layoutCache: context.layoutCache
      )
    }
    .onChange(of: appState.isEditorMotionSuppressed) { _, isSuppressed in
      guard isActive, !isSuppressed else { return }
      syncScheduleBoardCaches(
        filteredEvents: context.filteredEvents,
        backgroundEvents: context.backgroundEvents,
        taskSnapshot: context.taskSnapshot,
        layoutCache: context.layoutCache,
        layoutSourceSignature: context.layoutSourceSignature,
        force: false
      )
    }
    .onChange(of: isActive) { _, active in
      if active {
        Task {
          await reloadWorkspaceScheduleProjectDetails(for: activeProjectIDs)
        }
        syncScheduleBoardCaches(
          filteredEvents: context.filteredEvents,
          backgroundEvents: context.backgroundEvents,
          taskSnapshot: context.taskSnapshot,
          layoutCache: context.layoutCache,
          layoutSourceSignature: context.layoutSourceSignature,
          force: false
        )
        refreshCalendarOverlay(force: true)
      } else {
        cancelScheduleDayHeaderOverlay()
        calendarOverlayRefreshTask?.cancel()
        calendarOverlayRefreshTask = nil
      }
    }
    .onDisappear {
      onTaskDragProjectionChanged?(nil, nil)
      cancelScheduleDayHeaderOverlay()
      calendarOverlayRefreshTask?.cancel()
      calendarOverlayRefreshTask = nil
    }
  }

  func scheduleBoardViewportSection(
    geometry: GeometryProxy,
    context: ScheduleBoardBodyContext
  ) -> some View {
    ZStack(alignment: .topLeading) {
      scheduleBoardScrollShell(
        geometry: geometry,
        context: context
      )

      scheduleBoardTopLeftHeaderSection

      scheduleBoardInteractionOverlaySection

      scheduleBoardChromeSection

      scheduleRuntimeNoticeSection
    }
  }

  @ViewBuilder
  var scheduleRuntimeNoticeSection: some View {
    if let notice = scheduleRuntimeNotice {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: notice.symbol)
          .font(.system(size: ScheduleUITokens.Chrome.runtimeNoticeIconFontSize, weight: .semibold))
          .foregroundStyle(.secondary)
          .padding(.top, 1)

        VStack(alignment: .leading, spacing: 3) {
          Text(notice.title)
            .font(.system(size: ScheduleUITokens.Chrome.runtimeNoticeTitleFontSize, weight: .semibold))
            .foregroundStyle(.primary)

          Text(notice.message)
            .font(.system(size: ScheduleUITokens.Chrome.runtimeNoticeBodyFontSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: 360, alignment: .leading)
      .overlaySurface(
        cornerRadius: 12,
        strokeColor: .primary,
        style: scheduleOverlayCardStyle
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      .padding(.top, 12)
      .padding(.trailing, 12)
      .allowsHitTesting(false)
    }
  }

  func scheduleBoardScrollShell(
    geometry: GeometryProxy,
    context: ScheduleBoardBodyContext
  ) -> some View {
    let boardContentVersion = boardContentVersion(
      layoutSourceSignature: context.layoutSourceSignature
    )
    let pinnedTopVersion = pinnedTopVersion(
      layoutSourceSignature: context.layoutSourceSignature
    )

    return UnifiedScheduleBoardScrollView(
      boardSize: CGSize(width: boardWidth, height: boardHeight),
      titleColumnWidth: titleColumnWidth,
      headerHeight: headerHeight,
      dayColumnWidth: dayColumnWidth,
      boardContentVersion: boardContentVersion,
      pinnedLeftVersion: pinnedLeftVersion,
      pinnedTopVersion: pinnedTopVersion,
      scrollRequestGeneration: scrollRequestGeneration,
      publishesLiveOffsets: activeTaskDrag != nil || activeTaskResize != nil
        || activeCalendarDrag != nil || activeCalendarResize != nil,
      isDateBoundarySnappingEnabled: isDateBoundarySnappingEnabled,
      viewportState: scrollViewportState,
      offsetX: $horizontalOffsetX,
      offsetY: $verticalOffsetY,
      requestedOffsetX: $requestedOffsetX,
      requestedOffsetY: $requestedOffsetY
    ) {
      scheduleTimedGridSection(
        timedEntries: context.layoutCache.timedEntries,
        backgroundTimedEntries: context.layoutCache.backgroundTimedEntries
      )
    } pinnedLeft: {
      scheduleBoardLeftAxisSection
    } pinnedTop: {
      scheduleBoardHeaderRailSection(
        allDayEntries: context.layoutCache.allDayEntries,
        backgroundAllDayEntries: context.layoutCache.backgroundAllDayEntries,
        timedEntries: context.layoutCache.timedEntries,
        backgroundTimedEntries: context.layoutCache.backgroundTimedEntries
      )
    }
    .frame(width: geometry.size.width, height: geometry.size.height)
  }

  var scheduleBoardGeometryPreferenceSurface: some View {
    GeometryReader { proxy in
      let dragFrame = proxy.frame(in: .named(dragProjectionCoordinateSpaceName))
      let containerOrigin = proxy.frame(in: .named(workspaceMainPaneCoordinateSpaceName)).origin
      Color.clear
        .preference(
          key: ScheduleBoardGlobalFramePreferenceKey.self,
          value: dragFrame
        )
        .preference(
          key: TimelineDayHeaderOverlayPresentationPreferenceKey.self,
          value: isActive
            ? scheduleDayHeaderOverlayPresentation(containerOrigin: containerOrigin)
            : nil
        )
    }
  }
}
