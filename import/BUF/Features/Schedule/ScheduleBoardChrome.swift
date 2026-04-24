import AppKit
import SwiftUI

extension ScheduleBoardView {
  var scheduleBoardTopLeftHeaderSection: some View {
    topLeftHeaderOverlay
  }

  var scheduleBoardChromeSection: some View {
    overlayControls
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.top, 10)
      .padding(.leading, calendarMenuLeadingInset)
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
        Menu {
          ForEach(calendarSources) { source in
            Section(source.title) {
              Toggle(
                isOn: Binding(
                  get: { source.isVisible },
                  set: { _ in appState.toggleScheduleCalendarVisibility(source.id) }
                )
              ) {
                HStack(spacing: 8) {
                  Circle()
                    .fill(ColorHexCodec.color(from: source.colorHex) ?? .secondary)
                    .frame(width: 10, height: 10)
                  Text("캘린더 표시")
                }
              }

              Toggle(
                isOn: Binding(
                  get: { source.isBackgroundOnly },
                  set: { _ in appState.toggleScheduleCalendarBackgroundOnly(source.id) }
                )
              ) {
                Label("영향 없음", systemImage: "square.split.diagonal")
              }
            }
          }
        } label: {
          calendarMenuLabel
        }
        .menuStyle(.borderlessButton)
        .help("Calendars")
      }

    }
  }

  var calendarMenuLabel: some View {
    HStack(spacing: 6) {
      ZStack(alignment: .bottomTrailing) {
        Image(systemName: "calendar")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary.opacity(0.72))
          .offset(x: -4, y: 2)

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
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
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
      Rectangle()
        .fill(Color(nsColor: .systemGray).opacity(0.4))
        .frame(height: 3)
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
      Rectangle()
        .fill(Color(nsColor: .systemGray).opacity(0.4))
        .frame(height: 3)
    }
    .frame(width: dayColumnsWidth, height: headerHeight, alignment: .topLeading)
    .clipped()
  }

  func dayHeaderCell(day: Date, index: Int) -> some View {
    let isToday = calendar.isDate(day, inSameDayAs: today)
    let isWeekend = calendar.isDateInWeekend(day)
    let showsMonth = calendar.component(.day, from: day) == 1
    let dayNumberColor: Color =
      isToday
      ? .white
      : (isWeekend ? Color(red: 0.76, green: 0.24, blue: 0.22) : .primary)
    let weekdayColor: Color =
      isToday
      ? .accentColor
      : (isWeekend ? Color(red: 0.76, green: 0.24, blue: 0.22) : .secondary)

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
      [Date: [UUID: (title: String, items: [TimelineDayHeaderOverlayTaskItem])]] = [:]

    func appendDayHeaderTask(
      _ item: TimelineDayHeaderOverlayTaskItem,
      day: Date,
      projectID: UUID,
      projectTitle: String
    ) {
      var sectionsForDay = taskItemsByDayAndProject[day] ?? [:]
      var payload = sectionsForDay[projectID] ?? (title: projectTitle, items: [])
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
        projectTitle: descriptor.projectTitle
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
            projectTitle: descriptor.projectTitle
          )
        }
    }

    let sectionsByDay = taskItemsByDayAndProject.mapValues { sections in
      sections
        .map { projectID, payload in
          TimelineDayHeaderOverlayProjectSection(
            id: projectID,
            projectReference: .project(projectID),
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

    if isHovering {
      hoveredScheduleDayHeaderDate = normalizedDay
      scheduleDayHeaderHideWorkItem?.cancel()

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

    if hoveredScheduleDayHeaderDate == normalizedDay {
      hoveredScheduleDayHeaderDate = nil
    }
    scheduleDayHeaderShowWorkItem?.cancel()
    scheduleScheduleDayHeaderOverlayHideIfNeeded()
  }

  func scheduleScheduleDayHeaderOverlayHideIfNeeded() {
    guard hoveredScheduleDayHeaderDate == nil, !appState.isHoveringTimelineDayHeaderOverlay else {
      return
    }

    scheduleDayHeaderHideWorkItem?.cancel()
    let workItem = DispatchWorkItem {
      guard hoveredScheduleDayHeaderDate == nil, !appState.isHoveringTimelineDayHeaderOverlay else {
        return
      }
      activeScheduleDayHeaderDate = nil
    }
    scheduleDayHeaderHideWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + scheduleDayHeaderHideDelay, execute: workItem)
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

  func cancelScheduleDayHeaderOverlay() {
    scheduleDayHeaderShowWorkItem?.cancel()
    scheduleDayHeaderHideWorkItem?.cancel()
    scheduleDayHeaderShowWorkItem = nil
    scheduleDayHeaderHideWorkItem = nil
    hoveredScheduleDayHeaderDate = nil
    activeScheduleDayHeaderDate = nil
    appState.isHoveringTimelineDayHeaderOverlay = false
  }
}
