import AppKit
import SwiftUI

private struct CalendarPickerRow: View {
  let source: ScheduleCalendarSource
  let onCycle: () -> Void

  @State private var isHovering = false

  private var calendarColor: Color {
    ColorHexCodec.color(from: source.colorHex) ?? Color.secondary
  }

  var body: some View {
    Button(action: onCycle) {
      HStack(spacing: 10) {
        stateIcon
          .frame(width: 14, height: 14)

        Text(source.title)
          .font(.system(size: 13))
          .foregroundStyle(source.isVisible ? Color.primary : Color.primary.opacity(0.3))
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isHovering ? Color(nsColor: .controlBackgroundColor) : Color.clear)
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(stateHelp)
  }

  @ViewBuilder
  private var stateIcon: some View {
    if !source.isVisible {
      Image(systemName: "xmark")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Color.primary.opacity(0.25))
    } else if source.isBackgroundOnly {
      Image(systemName: "triangle.fill")
        .font(.system(size: 9))
        .foregroundStyle(calendarColor.opacity(0.55))
    } else {
      Image(systemName: "circle.fill")
        .font(.system(size: 9))
        .foregroundStyle(calendarColor)
    }
  }

  private var stateHelp: String {
    if !source.isVisible { return "숨김 → 클릭하면 활성으로" }
    if source.isBackgroundOnly { return "표시만 함 → 클릭하면 숨김으로" }
    return "활성 → 클릭하면 표시만으로"
  }
}

extension ScheduleBoardView {
  var scheduleBoardTopLeftHeaderSection: some View {
    topLeftHeaderOverlay
  }

  var scheduleBoardChromeSection: some View {
    overlayControls
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.top, -2)
      .padding(.leading, calendarMenuLeadingInset - 3)
  }

  func scheduleBoardHeaderRailSection(
    allDayEntries: [ScheduleAllDayLayout],
    backgroundAllDayEntries: [ScheduleAllDayLayout]
  ) -> some View {
    topHeaderContent(
      allDayEntries: allDayEntries,
      backgroundAllDayEntries: backgroundAllDayEntries
    )
  }

  @ViewBuilder
  var overlayControls: some View {
    let calendarSources = appState.resolvedScheduleCalendarOverlayProjection().calendarSources

    VStack(alignment: .leading, spacing: 8) {
      if !calendarSources.isEmpty {
        Button {
          isCalendarPickerShown.toggle()
        } label: {
          calendarMenuLabel
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isCalendarPickerShown, arrowEdge: .bottom) {
          calendarPickerPopover(sources: calendarSources)
        }
      }
    }
  }

  func calendarPickerPopover(sources: [ScheduleCalendarSource]) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("캘린더")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)

      ForEach(sources) { source in
        CalendarPickerRow(source: source) {
          cycleCalendarState(source: source)
        }
      }

      Divider()
        .padding(.horizontal, 6)
        .padding(.vertical, 4)

      HStack(spacing: 12) {
        calendarPickerLegendItem("circle.fill", opacity: 1.0, label: "활성")
        calendarPickerLegendItem("triangle.fill", opacity: 0.55, label: "표시만")
        calendarPickerLegendItem("xmark", opacity: 0.25, label: "숨김")
      }
      .font(.system(size: 10))
      .padding(.horizontal, 10)
      .padding(.bottom, 8)
    }
    .frame(minWidth: 190, maxWidth: 280)
  }

  func calendarPickerLegendItem(_ symbol: String, opacity: Double, label: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: symbol)
        .font(.system(size: 8))
        .foregroundStyle(Color.primary.opacity(opacity))
      Text(label)
        .foregroundStyle(.tertiary)
    }
  }

  func cycleCalendarState(source: ScheduleCalendarSource) {
    if !source.isVisible {
      appState.toggleScheduleCalendarVisibility(source.id)
      if source.isBackgroundOnly {
        appState.toggleScheduleCalendarBackgroundOnly(source.id)
      }
    } else if source.isBackgroundOnly {
      appState.toggleScheduleCalendarVisibility(source.id)
    } else {
      appState.toggleScheduleCalendarBackgroundOnly(source.id)
    }
  }

  var calendarMenuLabel: some View {
    HStack(spacing: 6) {
      ZStack(alignment: .bottomTrailing) {
        Image(systemName: "calendar")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)

        calendarMenuSwatches
          .padding(.horizontal, 4)
          .padding(.vertical, 2)
          .background(
            Capsule()
              .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
          )
          .offset(x: 8, y: 7)
      }

      Image(systemName: "chevron.down")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
    }
    .frame(height: 24)
    .contentShape(Rectangle())
    .accessibilityLabel("Calendars")
  }

  var calendarMenuSwatches: some View {
    let calendarSources = appState.resolvedScheduleCalendarOverlayProjection().calendarSources

    return HStack(spacing: 3) {
      ForEach(Array(calendarSources.prefix(3))) { source in
        Circle()
          .fill(ColorHexCodec.color(from: source.colorHex) ?? .secondary)
          .frame(width: 6, height: 6)
      }
    }
  }

  var topLeftHeaderOverlay: some View {
    VStack(spacing: 0) {
      Rectangle()
        .fill(Color(nsColor: .windowBackgroundColor))
        .frame(height: dateHeaderHeight)
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
        }

      HStack {
        Text("All-day")
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(.tertiary)
          .textCase(.uppercase)
          .padding(.trailing, 6)
      }
      .frame(
        maxWidth: .infinity,
        minHeight: allDayRailVisibleHeight,
        maxHeight: allDayRailVisibleHeight,
        alignment: .trailing
      )
      .background(Color.clear)
    }
    .frame(width: titleColumnWidth, height: headerHeight, alignment: .top)
    .background(
      Rectangle()
        .fill(Color(nsColor: .windowBackgroundColor))
    )
    .overlay(alignment: .trailing) {
      Rectangle()
        .fill(Color.primary.opacity(0.08))
        .frame(width: 1)
    }
    .overlay(alignment: .bottom) {
      allDayRailResizeDivider()
    }
  }

  func topHeaderContent(
    allDayEntries: [ScheduleAllDayLayout],
    backgroundAllDayEntries: [ScheduleAllDayLayout]
  ) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
          dayHeaderCell(day: day, index: index)
            .frame(width: dayColumnWidth, height: dateHeaderHeight)
            .background(dayHeaderBackground(day: day))
            .overlay(alignment: .trailing) {
              Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
            }
        }
      }
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(Color.primary.opacity(0.08))
          .frame(height: 1)
      }

      allDayRail(allDayEntries, backgroundEntries: backgroundAllDayEntries)
        .frame(width: dayColumnsWidth, height: allDayRailVisibleHeight)
    }
    .background(
      Rectangle()
        .fill(Color(nsColor: .windowBackgroundColor))
    )
    .overlay(alignment: .bottom) {
      allDayRailResizeDivider()
    }
    .frame(width: dayColumnsWidth, height: headerHeight, alignment: .topLeading)
    .clipped()
  }

  func allDayRailResizeDivider() -> some View {
    let dividerOpacity = isAllDayRailResizing ? 0.62 : 0.4
    let dividerHeight: CGFloat = isAllDayRailResizing ? 4 : 3

    return ZStack(alignment: .bottom) {
      Rectangle()
        .fill(Color(nsColor: .systemGray).opacity(dividerOpacity))
        .frame(height: dividerHeight)
    }
    .frame(height: 10, alignment: .bottom)
    .contentShape(Rectangle())
    .overlay {
      if canResizeAllDayRail {
        ScheduleCursorRegion(cursor: .resizeUpDown)
      }
    }
    .highPriorityGesture(allDayRailResizeGesture())
    .help("올데이 영역 높이 조절")
  }

  func allDayRailResizeGesture() -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .global)
      .onChanged { value in
        guard canResizeAllDayRail else {
          cancelAllDayRailResize()
          return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          updateAllDayRailResize(translationHeight: value.translation.height)
        }
      }
      .onEnded { _ in
        guard isAllDayRailResizing else {
          cancelAllDayRailResize()
          return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          commitAllDayRailResize()
        }
      }
  }

  func dayHeaderCell(day: Date, index: Int) -> some View {
    let isToday = calendar.isDate(day, inSameDayAs: today)
    let showsMonth = calendar.component(.day, from: day) == 1
    let dayNumberColor: Color =
      isToday
      ? .white
      : .primary
    let weekdayColor: Color =
      isToday
      ? .accentColor
      : .secondary

    return HStack(spacing: 7) {
      Text(dayHeaderDayNumber(day))
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(dayNumberColor)
        .frame(width: 24, height: 24)
        .background {
          if isToday {
            Circle()
              .fill(Color.accentColor)
          }
        }

      HStack(spacing: 4) {
        if showsMonth {
          Text(dayHeaderMonth(day))
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
        }

        Text(dayHeaderWeekday(day))
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(weekdayColor)
          .textCase(.uppercase)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(.horizontal, 10)
    .contentShape(Rectangle())
    .onHover { isHovering in
      updateScheduleDayHeaderHover(day: day, index: index, isHovering: isHovering)
    }
  }

  func dayHeaderBackground(day: Date) -> some View {
    Rectangle()
      .fill(dayColumnBackgroundColor(for: day, section: .header))
  }

  func dayHeaderWeekday(_ day: Date) -> String {
    Self.dayHeaderWeekdayFormatter.string(from: day).uppercased()
  }

  func dayHeaderDayNumber(_ day: Date) -> String {
    Self.dayHeaderDayNumberFormatter.string(from: day)
  }

  func dayHeaderMonth(_ day: Date) -> String {
    Self.dayHeaderMonthFormatter.string(from: day)
  }

  func scheduleDayHeaderPreviewTitle(for title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "제목 없음" : trimmed
  }

  func refreshedScheduleDayHeaderSourceSignature(taskSignature: Int) -> Int {
    var hasher = Hasher()
    hasher.combine(scheduleTaskSourceSignature)
    hasher.combine(taskSignature)
    return hasher.finalize()
  }

  func scheduleWorkspaceDayHeaderTaskSort(
    lhs: WorkspaceScheduleTaskDescriptor,
    rhs: WorkspaceScheduleTaskDescriptor
  ) -> Bool {
    if lhs.projectTitle != rhs.projectTitle {
      return lhs.projectTitle.localizedStandardCompare(rhs.projectTitle) == .orderedAscending
    }
    if lhs.taskRow.rowOrder != rhs.taskRow.rowOrder {
      return lhs.taskRow.rowOrder < rhs.taskRow.rowOrder
    }
    if lhs.taskRow.createdAt != rhs.taskRow.createdAt {
      return lhs.taskRow.createdAt < rhs.taskRow.createdAt
    }
    return lhs.taskRow.title.localizedStandardCompare(rhs.taskRow.title) == .orderedAscending
  }

  func refreshScheduleDayHeaderSectionsIfNeeded(
    sourceSignature: Int,
    force: Bool
  ) {
    if !force,
      let cachedScheduleDayHeaderSourceSignature,
      cachedScheduleDayHeaderSourceSignature == sourceSignature
    {
      return
    }

    var taskItemsByDayAndProject:
      [Date: [UUID: (title: String, colorHex: String?, items: [TimelineDayHeaderOverlayTaskItem])]]
      = [:]

    func appendDayHeaderTask(
      _ item: TimelineDayHeaderOverlayTaskItem,
      day: Date,
      projectID: UUID,
      projectTitle: String,
      projectColorHex: String?
    ) {
      var sectionsForDay = taskItemsByDayAndProject[day] ?? [:]
      var payload =
        sectionsForDay[projectID]
        ?? (title: projectTitle, colorHex: projectColorHex, items: [])
      payload.items.append(item)
      sectionsForDay[projectID] = payload
      taskItemsByDayAndProject[day] = sectionsForDay
    }

    for descriptor in workspaceScheduleTasks.sorted(by: scheduleWorkspaceDayHeaderTaskSort) {
      let task = descriptor.taskRow
      guard shouldDisplayScheduledWorkspaceTask(task),
        let scheduledDay = scheduleDay(for: task)
      else {
        continue
      }

      let day = calendar.startOfDay(for: scheduledDay)
      let title = scheduleDayHeaderPreviewTitle(for: task.title)
      let projectID = descriptor.projectID
      let reference = WorkspaceProjectReference.project(projectID)

      appendDayHeaderTask(
        TimelineDayHeaderOverlayTaskItem(
          id: "\(projectID.uuidString)-\(task.id.uuidString)-scheduled",
          projectReference: reference,
          taskID: task.id,
          title: title,
          isCompleted: task.isCompleted,
          isOverdue: !task.isCompleted && day < today
        ),
        day: day,
        projectID: projectID,
        projectTitle: descriptor.projectTitle,
        projectColorHex: descriptor.projectColorHex
      )

      if !task.isCompleted, day < today {
        appendDayHeaderTask(
          TimelineDayHeaderOverlayTaskItem(
            id: "\(reference.id.uuidString)-\(task.id.uuidString)-overdue-today",
            projectReference: reference,
            taskID: task.id,
            title: title,
            isCompleted: false,
            isOverdue: true
            ),
            day: today,
            projectID: projectID,
            projectTitle: descriptor.projectTitle,
            projectColorHex: descriptor.projectColorHex
          )
        }
    }

    let sectionsByDay = taskItemsByDayAndProject.mapValues { sections in
      sections
        .map { projectID, payload in
          TimelineDayHeaderOverlayProjectSection(
            id: projectID,
            projectReference: .project(projectID),
            projectColorHex: payload.colorHex,
            projectTitle: payload.title,
            tasks: payload.items
          )
        }
        .sorted { lhs, rhs in
          lhs.projectTitle.localizedStandardCompare(rhs.projectTitle) == .orderedAscending
        }
    }

    cachedScheduleDayHeaderSections = sectionsByDay
    cachedScheduleDayHeaderSourceSignature = sourceSignature
  }

  func scheduleDayHeaderOverlayPresentation(containerOrigin: CGPoint)
    -> TimelineDayHeaderOverlayPresentation?
  {
    guard !appState.isEditorMotionSuppressed,
      let activeScheduleDayHeaderDate,
      let index = dayIndex(of: activeScheduleDayHeaderDate),
      isScheduleDayHeaderInteractable(index)
    else {
      return nil
    }

    let activeDate = calendar.startOfDay(for: activeScheduleDayHeaderDate)
    guard let sections = cachedScheduleDayHeaderSections[activeDate], !sections.isEmpty else {
      return nil
    }

    let overlayHeight = scheduleDayHeaderOverlayEstimatedHeight(for: sections)
    let overlayX = scheduleDayHeaderOverlayX(for: index)
    return TimelineDayHeaderOverlayPresentation(
      frame: CGRect(
        x: containerOrigin.x + titleColumnWidth + overlayX - horizontalOffsetX,
        y: containerOrigin.y + headerHeight,
        width: scheduleDayHeaderOverlayWidth,
        height: overlayHeight
      ),
      date: activeDate,
      sections: sections
    )
  }

  func scheduleDayHeaderOverlayEstimatedHeight(
    for sections: [TimelineDayHeaderOverlayProjectSection]
  ) -> CGFloat {
    let verticalPadding: CGFloat = 24
    let sectionHeaderHeight: CGFloat = 18
    let rowHeightEstimate: CGFloat = 22
    let rowSpacing: CGFloat = 8
    let dividerBlockHeight: CGFloat = 19

    var total: CGFloat = verticalPadding
    for (index, section) in sections.enumerated() {
      total += sectionHeaderHeight
      total += CGFloat(section.tasks.count) * rowHeightEstimate
      total += CGFloat(max(0, section.tasks.count - 1)) * rowSpacing
      if index < sections.count - 1 {
        total += dividerBlockHeight
      }
    }
    return total
  }

  func scheduleDayHeaderOverlayX(for index: Int) -> CGFloat {
    let minInset: CGFloat = 8
    let maxX = max(minInset, dayColumnsWidth - scheduleDayHeaderOverlayWidth - minInset)
    let cellMidX = CGFloat(index) * dayColumnWidth + (dayColumnWidth * 0.5)
    return min(maxX, max(minInset, cellMidX - 32))
  }

  func dayIndex(of date: Date) -> Int? {
    days.firstIndex { calendar.isDate($0, inSameDayAs: date) }
  }

  func updateScheduleDayHeaderHover(day: Date, index: Int, isHovering: Bool) {
    let normalizedDay = calendar.startOfDay(for: day)
    if appState.isEditorMotionSuppressed || !isScheduleDayHeaderInteractable(index) {
      if isHovering {
        cancelScheduleDayHeaderOverlay()
      }
      return
    }

    if isHovering, shouldDeferScheduleDayHeaderHover(normalizedDay) {
      clearScheduleDayHeaderTriggerHover(deferClose: true)
      return
    }

    if isHovering {
      scheduleDayHeaderDetachWorkItem?.cancel()
      scheduleDayHeaderDetachWorkItem = nil
      hoveredScheduleDayHeaderDate = normalizedDay

      if activeScheduleDayHeaderDate == normalizedDay {
        return
      }

      scheduleDayHeaderShowWorkItem?.cancel()
      let workItem = DispatchWorkItem {
        guard hoveredScheduleDayHeaderDate == normalizedDay else { return }
        activeScheduleDayHeaderDate = normalizedDay
      }
      scheduleDayHeaderShowWorkItem = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + scheduleDayHeaderShowDelay, execute: workItem)
      return
    }

    clearScheduleDayHeaderTriggerHover(day: normalizedDay, deferClose: true)
  }

  func shouldDeferScheduleDayHeaderHover(_ day: Date) -> Bool {
    if appState.isHoveringTimelineDayHeaderOverlay, activeScheduleDayHeaderDate != nil {
      return true
    }

    if let activeScheduleDayHeaderDate, activeScheduleDayHeaderDate != day {
      return true
    }

    return false
  }

  func dismissScheduleDayHeaderHoverIfObscured() {
    if let hoveredScheduleDayHeaderDate,
      let hoveredIndex = dayIndex(of: hoveredScheduleDayHeaderDate),
      !isScheduleDayHeaderInteractable(hoveredIndex)
    {
      cancelScheduleDayHeaderOverlay()
      return
    }

    if let activeScheduleDayHeaderDate,
      let activeIndex = dayIndex(of: activeScheduleDayHeaderDate),
      !isScheduleDayHeaderInteractable(activeIndex)
    {
      cancelScheduleDayHeaderOverlay()
    }
  }

  func isScheduleDayHeaderInteractable(_ index: Int) -> Bool {
    index >= currentVisibleLowerDayIndex
  }

  var currentVisibleLowerDayIndex: Int {
    guard !days.isEmpty else { return 0 }
    let raw = Int(floor(max(0, horizontalOffsetX) / dayColumnWidth))
    return min(max(raw, 0), max(0, days.count - 1))
  }

  func clearScheduleDayHeaderTriggerHover(
    day: Date? = nil,
    deferClose: Bool = false
  ) {
    guard day == nil
      || hoveredScheduleDayHeaderDate == day
      || (hoveredScheduleDayHeaderDate == nil && activeScheduleDayHeaderDate == day)
    else {
      return
    }

    if day == nil || hoveredScheduleDayHeaderDate == day {
      scheduleDayHeaderShowWorkItem?.cancel()
      scheduleDayHeaderShowWorkItem = nil
      hoveredScheduleDayHeaderDate = nil
    }
    dismissScheduleDayHeaderOverlayIfDetached(deferClose: deferClose)
  }

  func dismissScheduleDayHeaderOverlayIfDetached(deferClose: Bool = false) {
    scheduleDayHeaderDetachWorkItem?.cancel()
    scheduleDayHeaderDetachWorkItem = nil

    let closeIfDetached = {
      guard hoveredScheduleDayHeaderDate == nil,
        !appState.isHoveringTimelineDayHeaderOverlay
      else {
        return
      }
      scheduleDayHeaderShowWorkItem?.cancel()
      scheduleDayHeaderShowWorkItem = nil
      scheduleDayHeaderDetachWorkItem?.cancel()
      scheduleDayHeaderDetachWorkItem = nil
      activeScheduleDayHeaderDate = nil
    }

    if deferClose {
      let workItem = DispatchWorkItem {
        closeIfDetached()
      }
      scheduleDayHeaderDetachWorkItem = workItem
      DispatchQueue.main.asyncAfter(
        deadline: .now() + scheduleOverlayDetachGraceDelay,
        execute: workItem
      )
    } else {
      closeIfDetached()
    }
  }

  func cancelScheduleDayHeaderOverlay() {
    scheduleDayHeaderShowWorkItem?.cancel()
    scheduleDayHeaderShowWorkItem = nil
    scheduleDayHeaderDetachWorkItem?.cancel()
    scheduleDayHeaderDetachWorkItem = nil
    hoveredScheduleDayHeaderDate = nil
    activeScheduleDayHeaderDate = nil
    appState.isHoveringTimelineDayHeaderOverlay = false
  }
}
