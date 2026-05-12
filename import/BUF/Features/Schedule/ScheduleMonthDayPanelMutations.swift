import AppKit
import SwiftUI

extension ScheduleMonthDaySchedulePanel {
  func toggleCompletion(for item: ScheduleMonthItem) {
    guard case .workspaceTask = item.source else { return }
    guard !savingItemIDs.contains(item.id) else { return }
    let next = !item.isCompleted
    let optimistic = item.replacing(isCompleted: next)
    replaceItem(optimistic)
    savingItemIDs.insert(item.id)
    Task { @MainActor in
      defer { savingItemIDs.remove(item.id) }
      guard let saved = await onToggleTaskCompletion(item, next) else {
        replaceItem(item)
        return
      }
      replaceItem(saved)
    }
  }

  func deleteItem(
    _ item: ScheduleMonthItem,
    scope: ScheduleCalendarRecurringEditScope?
  ) {
    guard !savingItemIDs.contains(item.id) else { return }
    let previousItems = items
    removeItem(item.id)
    savingItemIDs.insert(item.id)
    Task { @MainActor in
      defer { savingItemIDs.remove(item.id) }
      guard await onDeleteItem(item, scope) else {
        items = previousItems
        return
      }
    }
  }

  func commitMutationSession(
    _ session: ScheduleInteractionSession,
    item: ScheduleMonthItem,
    itemID: String
  ) {
    activeMutationPreview = nil
    activeItemDragState = nil
    activeItemResizeState = nil
    guard canUpdateSchedule(for: item) else { return }
    guard !savingItemIDs.contains(item.id) else { return }
    guard let command = session.command else { return }
    let commandPreview = command
      .schedulePreview(fallbackDay: calendar.startOfDay(for: target.date))
      .monthDayPreview(itemID: itemID, fallbackDay: calendar.startOfDay(for: target.date))
    let updated = item.applyingSchedulePreview(commandPreview, calendar: calendar)
    guard updated.startDate != item.startDate
      || updated.endDate != item.endDate
      || updated.isAllDay != item.isAllDay
    else {
      return
    }

    replaceOrRemoveForCurrentDay(updated)
    savingItemIDs.insert(item.id)
    Task { @MainActor in
      defer { savingItemIDs.remove(item.id) }
      guard
        let saved = await onUpdateItemSchedule(
          item,
          commandPreview.day,
          commandPreview.timeMinutes,
          commandPreview.durationMinutes
        )
      else {
        replaceOrRemoveForCurrentDay(item)
        return
      }
      replaceOrRemoveForCurrentDay(saved)
    }
  }
}
