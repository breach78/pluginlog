import Foundation
import SwiftUI

@MainActor
final class WorkspaceChromeState: ObservableObject {
  @Published private(set) var debouncedProjectFilterToken: String = ""
  @Published var workspaceSearchQuery: String = ""
  @Published private(set) var debouncedWorkspaceSearchQuery: String = ""
  @Published var selectedWorkspaceSearchResultIndex: Int = 0
  @Published var workspaceSearchFocused = false
  @Published private(set) var workspaceSearchFocusRequestID = 0
  @Published private(set) var loadedViewModes: Set<ViewMode> = []
  @Published var showSyncQuickAddPopover = false

  private let projectOrderingCache = ProjectOrderingCache()
  private var projectFilterDebounceTask: Task<Void, Never>?
  private var workspaceSearchDebounceTask: Task<Void, Never>?

  deinit {
    projectFilterDebounceTask?.cancel()
    workspaceSearchDebounceTask?.cancel()
  }

  func orderedVisibleProjectDescriptors(
    descriptors: [WorkspaceProjectDescriptor],
    mode: ProjectListSortMode,
    boardRevision: Int
  ) -> [WorkspaceProjectDescriptor] {
    projectOrderingCache.orderedVisibleProjectDescriptors(
      descriptors: descriptors,
      mode: mode,
      boardRevision: boardRevision
    )
  }

  func timelineOrderedProjectDescriptors(
    descriptors: [WorkspaceProjectDescriptor],
    mode: ProjectListSortMode,
    boardRevision: Int
  ) -> [WorkspaceProjectDescriptor] {
    projectOrderingCache.timelineOrderedProjectDescriptors(
      descriptors: descriptors,
      mode: mode,
      boardRevision: boardRevision
    )
  }

  func refreshProjectFilterImmediately(from raw: String) {
    debouncedProjectFilterToken = normalizedSearchToken(from: raw)
  }

  func scheduleProjectFilterDebounce(for raw: String) {
    projectFilterDebounceTask?.cancel()
    projectFilterDebounceTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(180))
      } catch {
        return
      }

      guard let self else { return }
      guard !Task.isCancelled else { return }
      self.debouncedProjectFilterToken = self.normalizedSearchToken(from: raw)
    }
  }

  func refreshWorkspaceSearchImmediately() {
    let trimmedQuery = workspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    if debouncedWorkspaceSearchQuery != trimmedQuery {
      debouncedWorkspaceSearchQuery = trimmedQuery
    }
    if trimmedQuery.isEmpty, selectedWorkspaceSearchResultIndex != 0 {
      selectedWorkspaceSearchResultIndex = 0
    }
  }

  func scheduleWorkspaceSearchDebounce(for raw: String) {
    workspaceSearchDebounceTask?.cancel()

    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      debouncedWorkspaceSearchQuery = ""
      selectedWorkspaceSearchResultIndex = 0
      return
    }

    workspaceSearchDebounceTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(120))
      } catch {
        return
      }

      guard let self else { return }
      guard !Task.isCancelled else { return }
      self.debouncedWorkspaceSearchQuery = trimmed
    }
  }

  func resetWorkspaceSearchSelection() {
    guard selectedWorkspaceSearchResultIndex != 0 else { return }
    selectedWorkspaceSearchResultIndex = 0
  }

  func clampWorkspaceSearchSelection(resultCount: Int) {
    guard resultCount > 0 else {
      selectedWorkspaceSearchResultIndex = 0
      return
    }
    selectedWorkspaceSearchResultIndex = min(selectedWorkspaceSearchResultIndex, resultCount - 1)
  }

  func focusWorkspaceSearch() {
    workspaceSearchFocused = true
    workspaceSearchFocusRequestID += 1
  }

  func dismissWorkspaceSearch() {
    workspaceSearchFocused = false
  }

  func clearWorkspaceSearch() {
    workspaceSearchDebounceTask?.cancel()
    workspaceSearchQuery = ""
    debouncedWorkspaceSearchQuery = ""
    selectedWorkspaceSearchResultIndex = 0
  }

  func syncBoardLoadingState(isLoaded: Bool, currentMode: ViewMode) {
    guard isLoaded else {
      if !loadedViewModes.isEmpty {
        loadedViewModes.removeAll(keepingCapacity: true)
      }
      return
    }
    loadedViewModes.insert(currentMode)
  }

  func shouldRenderBoard(currentMode: ViewMode, candidateMode: ViewMode) -> Bool {
    currentMode == candidateMode || loadedViewModes.contains(candidateMode)
  }

  func toggleSyncQuickAddPopover() {
    showSyncQuickAddPopover.toggle()
  }

  func dismissSyncQuickAddPopover() {
    showSyncQuickAddPopover = false
    workspaceSearchFocused = false
  }

  func cancelPendingTasks() {
    projectFilterDebounceTask?.cancel()
    workspaceSearchDebounceTask?.cancel()
  }

  private func normalizedSearchToken(from raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private final class ProjectOrderingCache {
  private struct Entry {
    let signature: Int
    let descriptors: [WorkspaceProjectDescriptor]
  }

  private var sidebarEntry: Entry?
  private var timelineEntry: Entry?

  func orderedVisibleProjectDescriptors(
    descriptors: [WorkspaceProjectDescriptor],
    mode: ProjectListSortMode,
    boardRevision: Int
  ) -> [WorkspaceProjectDescriptor] {
    let signature = makeSignature(
      descriptors: descriptors,
      mode: mode,
      boardRevision: boardRevision,
      timeline: false
    )
    if let entry = sidebarEntry, entry.signature == signature {
      return entry.descriptors
    }

    let ordered = ProjectOrdering.ordered(descriptors, mode: mode)
    sidebarEntry = Entry(signature: signature, descriptors: ordered)
    return ordered
  }

  func timelineOrderedProjectDescriptors(
    descriptors: [WorkspaceProjectDescriptor],
    mode: ProjectListSortMode,
    boardRevision: Int
  ) -> [WorkspaceProjectDescriptor] {
    let signature = makeSignature(
      descriptors: descriptors,
      mode: mode,
      boardRevision: boardRevision,
      timeline: true
    )
    if let entry = timelineEntry, entry.signature == signature {
      return entry.descriptors
    }

    let ordered = ProjectOrdering.orderedForTimeline(descriptors, mode: mode)
    timelineEntry = Entry(signature: signature, descriptors: ordered)
    return ordered
  }

  private func makeSignature(
    descriptors: [WorkspaceProjectDescriptor],
    mode: ProjectListSortMode,
    boardRevision: Int,
    timeline: Bool
  ) -> Int {
    var hasher = Hasher()
    hasher.combine(mode)
    hasher.combine(boardRevision)
    hasher.combine(timeline)
    hasher.combine(descriptors.count)
    for descriptor in descriptors {
      hasher.combine(descriptor.id)
      hasher.combine(descriptor.workspaceSortKey)
      hasher.combine(descriptor.title)
      hasher.combine(descriptor.updatedAt.timeIntervalSinceReferenceDate)
      hasher.combine(descriptor.latestTaskUpdatedAt?.timeIntervalSinceReferenceDate)
      hasher.combine(descriptor.stage)
      hasher.combine(descriptor.isArchived)
    }

    return hasher.finalize()
  }
}
