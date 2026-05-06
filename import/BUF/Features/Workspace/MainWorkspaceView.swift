import AppKit
import SwiftData
import SwiftUI

// Composition root only.
// Budget + split fence enforced by MainWorkspaceReductionMilestoneTests.swift.
// Diagnostics ownership: MainWorkspaceDiagnostics.swift
// Chrome ownership: MainWorkspaceChrome.swift
// Sidebar ownership: MainWorkspaceSidebar.swift
// Panel routing ownership: MainWorkspacePanels.swift
// Search ownership: MainWorkspaceSearch.swift
// Overlay ownership: MainWorkspaceOverlays.swift
// Action ownership: MainWorkspaceActions.swift

struct WorkspaceQuickAddProjectOption: Identifiable, Hashable {
  let id: UUID
  let title: String
}

struct WorkspaceProjectDescriptor: Identifiable, Hashable {
  let id: UUID
  let title: String
  let colorHex: String?
  let reminderListIdentifier: String
  let updatedAt: Date
  let createdAt: Date
  let latestTaskUpdatedAt: Date?
  let isArchived: Bool
  let stage: ProjectProgressStage
  let boardOrder: Int?
  let workspaceSortKey: Int64?

  init(
    id: UUID,
    title: String,
    colorHex: String?,
    reminderListIdentifier: String,
    updatedAt: Date,
    createdAt: Date,
    latestTaskUpdatedAt: Date?,
    isArchived: Bool,
    stage: ProjectProgressStage,
    boardOrder: Int? = nil,
    workspaceSortKey: Int64?
  ) {
    self.id = id
    self.title = title
    self.colorHex = colorHex
    self.reminderListIdentifier = reminderListIdentifier
    self.updatedAt = updatedAt
    self.createdAt = createdAt
    self.latestTaskUpdatedAt = latestTaskUpdatedAt
    self.isArchived = isArchived
    self.stage = stage
    self.boardOrder = boardOrder
    self.workspaceSortKey = workspaceSortKey
  }

  var latestActivityAt: Date {
    latestTaskUpdatedAt ?? updatedAt
  }
}

struct WorkspaceQuickAddPopoverContent: View {
  let projects: [WorkspaceQuickAddProjectOption]
  let onSubmit: (String, UUID) -> Void
  let onCancel: () -> Void

  @State private var title: String = ""
  @State private var selectedProjectID: UUID?
  @State private var isFieldFocused = false

  init(
    projects: [WorkspaceQuickAddProjectOption],
    defaultProjectID: UUID?,
    onSubmit: @escaping (String, UUID) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.projects = projects
    self.onSubmit = onSubmit
    self.onCancel = onCancel
    _selectedProjectID = State(initialValue: defaultProjectID ?? projects.first?.id)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("할일 추가")
        .font(.system(size: 12, weight: .semibold))

      EscapeAwareTextField(
        text: $title,
        isFocused: $isFieldFocused,
        placeholder: "할일 입력",
        onSubmit: submit,
        onEscape: onCancel
      )
      .frame(height: 22)

      Menu {
        ForEach(projects) { project in
          Button {
            selectedProjectID = project.id
          } label: {
            if selectedProjectID == project.id {
              Label(project.title, systemImage: "checkmark")
            } else {
              Text(project.title)
            }
          }
        }
      } label: {
        HStack(spacing: 8) {
          Text(selectedProjectTitle)
            .lineLimit(1)
          Spacer(minLength: 0)
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
        )
      }
      .menuStyle(.borderlessButton)

      HStack(spacing: 8) {
        Spacer(minLength: 0)

        Button("취소") {
          onCancel()
        }

        Button("추가") {
          submit()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedProjectID == nil
        )
      }
    }
    .padding(12)
    .frame(width: 260)
    .onAppear {
      DispatchQueue.main.async {
        isFieldFocused = true
      }
    }
    .onExitCommand {
      onCancel()
    }
  }

  private var selectedProjectTitle: String {
    projects.first(where: { $0.id == selectedProjectID })?.title ?? "목록 선택"
  }

  private func submit() {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let selectedProjectID else { return }
    onSubmit(trimmed, selectedProjectID)
  }
}

struct WorkspaceNewProjectPopoverContent: View {
  let isCreating: Bool
  let onSubmit: (String) -> Void
  let onCancel: () -> Void

  @State private var title: String = ""
  @FocusState private var isFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("새 프로젝트")
        .font(.system(size: 12, weight: .semibold))

      TextField("프로젝트 이름", text: $title)
        .textFieldStyle(.roundedBorder)
        .font(AppInputTypography.font(size: AppInputTypography.defaultPointSize))
        .focused($isFieldFocused)
        .onSubmit {
          submit()
        }

      HStack(spacing: 8) {
        Spacer(minLength: 0)

        Button("취소") {
          onCancel()
        }

        Button(isCreating ? "생성 중..." : "추가") {
          submit()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!canSubmit)
      }
    }
    .padding(12)
    .frame(width: 260)
    .onAppear {
      DispatchQueue.main.async {
        isFieldFocused = true
      }
    }
    .onExitCommand {
      onCancel()
    }
  }

  private func submit() {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isCreating else { return }
    onSubmit(trimmed)
  }

  private var canSubmit: Bool {
    !isCreating && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

struct WorkspaceRenameProjectSheetContent: View {
  let originalTitle: String
  let isRenaming: Bool
  let onSubmit: (String) -> Void
  let onCancel: () -> Void

  var body: some View {
    WorkspaceProjectTitleSheetContent(
      heading: "프로젝트 이름 변경",
      initialTitle: originalTitle,
      submitTitle: "변경",
      inFlightSubmitTitle: "변경 중...",
      isSubmitting: isRenaming,
      requiresChangedTitle: true,
      onSubmit: onSubmit,
      onCancel: onCancel
    )
  }
}

struct WorkspaceRenameAttachmentSheetContent: View {
  let originalNameStem: String
  let fixedExtension: String?
  let isRenaming: Bool
  let onSubmit: (String) -> Void
  let onCancel: () -> Void

  var body: some View {
    WorkspaceProjectTitleSheetContent(
      heading: "첨부파일 이름 변경",
      fieldPrompt: "첨부파일 이름",
      initialTitle: originalNameStem,
      fixedSuffix: fixedExtension.map { ".\($0)" },
      submitTitle: "변경",
      inFlightSubmitTitle: "변경 중...",
      isSubmitting: isRenaming,
      requiresChangedTitle: true,
      onSubmit: onSubmit,
      onCancel: onCancel
    )
  }
}

struct WorkspaceNewProjectSheetContent: View {
  let isCreating: Bool
  let onSubmit: (String) -> Void
  let onCancel: () -> Void

  var body: some View {
    WorkspaceProjectTitleSheetContent(
      heading: "새 프로젝트",
      initialTitle: "",
      submitTitle: "추가",
      inFlightSubmitTitle: "생성 중...",
      isSubmitting: isCreating,
      requiresChangedTitle: false,
      onSubmit: onSubmit,
      onCancel: onCancel
    )
  }
}

private struct WorkspaceProjectTitleSheetContent: View {
  let heading: String
  let fieldPrompt: String
  let initialTitle: String
  let fixedSuffix: String?
  let submitTitle: String
  let inFlightSubmitTitle: String
  let isSubmitting: Bool
  let requiresChangedTitle: Bool
  let onSubmit: (String) -> Void
  let onCancel: () -> Void

  @State private var title: String
  @FocusState private var isFieldFocused: Bool

  init(
    heading: String,
    fieldPrompt: String = "프로젝트 이름",
    initialTitle: String,
    fixedSuffix: String? = nil,
    submitTitle: String,
    inFlightSubmitTitle: String,
    isSubmitting: Bool,
    requiresChangedTitle: Bool,
    onSubmit: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.heading = heading
    self.fieldPrompt = fieldPrompt
    self.initialTitle = initialTitle
    self.fixedSuffix = fixedSuffix
    self.submitTitle = submitTitle
    self.inFlightSubmitTitle = inFlightSubmitTitle
    self.isSubmitting = isSubmitting
    self.requiresChangedTitle = requiresChangedTitle
    self.onSubmit = onSubmit
    self.onCancel = onCancel
    _title = State(initialValue: initialTitle)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(heading)
        .font(.system(size: 14, weight: .semibold))

      titleInput

      HStack(spacing: 8) {
        Spacer(minLength: 0)

        Button("취소") {
          onCancel()
        }

        Button(isSubmitting ? inFlightSubmitTitle : submitTitle) {
          submit()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!canSubmit)
      }
    }
    .padding(18)
    .frame(width: 340)
    .onAppear {
      DispatchQueue.main.async {
        isFieldFocused = true
      }
    }
    .onExitCommand {
      onCancel()
    }
  }

  private var canSubmit: Bool {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let initialTrimmed = initialTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return !isSubmitting
      && !trimmed.isEmpty
      && (!requiresChangedTitle || trimmed != initialTrimmed)
  }

  private func submit() {
    guard canSubmit else { return }
      onSubmit(title.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  @ViewBuilder
  private var titleInput: some View {
    if let fixedSuffix {
      HStack(spacing: 6) {
        titleField
        Text(fixedSuffix)
          .font(AppInputTypography.font(size: AppInputTypography.defaultPointSize))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    } else {
      titleField
    }
  }

  private var titleField: some View {
    TextField(fieldPrompt, text: $title)
      .textFieldStyle(.roundedBorder)
      .font(AppInputTypography.font(size: AppInputTypography.defaultPointSize))
      .focused($isFieldFocused)
      .onSubmit {
        submit()
      }
  }
}

struct WorkspaceProjectSortButton: View {
  @Binding var sortMode: ProjectListSortMode
  let context: ProjectListSortPresentationContext
  let fillsWidth: Bool

  init(
    sortMode: Binding<ProjectListSortMode>,
    context: ProjectListSortPresentationContext,
    fillsWidth: Bool = false
  ) {
    _sortMode = sortMode
    self.context = context
    self.fillsWidth = fillsWidth
  }

  var body: some View {
    Button(action: toggleSortMode) {
      HStack(spacing: 6) {
        if let indicatorIconName = sortMode.indicatorIconName {
          Image(systemName: indicatorIconName)
            .font(.caption.weight(.semibold))
        }
        Text("Projects")
          .font(.caption.weight(.semibold))
      }
      .foregroundStyle(.secondary)
      .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(sortMode.helpText(in: context))
  }

  private func toggleSortMode() {
    switch context {
    case .sidebar:
      sortMode = sortMode.nextSidebar
    case .timeline:
      sortMode = sortMode.nextTimeline
    }
  }
}

enum WorkspaceUserDefaultsKey {
  static let sidebarProjectListSortMode = "workspace.sidebarProjectListSortMode"
  static let timelineProjectListSortMode = "workspace.timelineProjectListSortMode"
  static let timelineProjectListSortModeReminderOrderMigration =
    "workspace.timelineProjectListSortModeReminderOrderMigration"
  static let timelineShowsHiddenProjectLists = "workspace.timelineShowsHiddenProjectLists"
}

struct MainWorkspaceView: View {
  @AppStorage(WorkspaceUserDefaultsKey.sidebarProjectListSortMode)
  var projectListSortModeRaw = ProjectListSortMode.manual.rawValue
  @AppStorage(WorkspaceUserDefaultsKey.timelineProjectListSortMode)
  var timelineProjectListSortModeRaw = ProjectListSortMode.manual.rawValue
  @AppStorage(WorkspaceUserDefaultsKey.timelineShowsHiddenProjectLists)
  var timelineShowsHiddenProjectLists = false
  @AppStorage(ProjectProgressStage.boardOrderRevisionStorageKey)
  var projectBoardOrderRevision = 0
  @EnvironmentObject var appState: AppState
  @Environment(\.modelContext) var modelContext
  @Environment(\.undoManager) var undoManager

  @StateObject var chromeState = WorkspaceChromeState()
  @State var workspaceSidebarProjects: [WorkspaceSidebarProjectItem] = []
  @State var workspaceOnlySearchResults: [WorkspaceSearchResult] = []
  @State var inspectorSelection: UUID?
  @State var localKeyMonitor: Any?
  @State var localMouseDownMonitor: Any?
  @State var pendingPermanentDeleteProject: PendingPermanentDeleteProject?
  @State var showInitialSyncAlert = false
  @State var sidebarTaskDropTargetProjectID: UUID?
  @State var showSidebarAddProjectPopover = false
  @State var isCreatingSidebarProject = false
  @State var pendingRenameProject: PendingProjectRename?
  @State var isRenamingProject = false
  @State var isRollingOverdueTasksToToday = false
  @State var activeWorkspaceProjectListPanelProjectID: UUID?
  @State var activeWorkspaceTaskEditPanelTarget: WorkspaceTaskEditPanelTarget?
  @State var activeWorkspaceCalendarEventEditPanelTarget: WorkspaceCalendarEventEditPanelTarget?
  @State var hiddenTimelineProjectIDs = TimelineHiddenProjectStore.load()

  struct ProjectSortOrderUndoSnapshot {
    let sortOrdersByProjectID: [UUID: Int]
  }

  struct ProjectBucketOrderUndoSnapshot {
    let boardOrdersByProjectID: [UUID: Int?]
  }

  struct PendingPermanentDeleteProject: Equatable {
    let id: UUID
    let title: String
  }

  struct PendingProjectRename: Identifiable, Equatable {
    let id: UUID
    let title: String
  }

  struct WorkspaceShellSnapshot {
    let filteredProjectIDs: [UUID]
    let filteredSidebarProjectIDs: [UUID]
    let searchResults: [WorkspaceSearchResult]
    let searchResultIDs: [String]
    let selectedSearchResult: WorkspaceSearchResult?
    let isSearchPanelVisible: Bool
  }

  enum WorkspaceProjectReadPath {
    static func sidebarProjectIDs(
      in sidebarProjects: [WorkspaceSidebarProjectItem]
    ) -> [UUID] {
      sidebarProjects.compactMap(\.projectID)
    }

    static func missingProjectIDNodeIDs(
      in sidebarProjects: [WorkspaceSidebarProjectItem]
    ) -> Set<UUID> {
      Set(
        sidebarProjects
          .filter { $0.projectID == nil }
          .map(\.nodeID)
      )
    }

    static func duplicateVisibleProjectIDs(
      in sidebarProjects: [WorkspaceSidebarProjectItem]
    ) -> Set<UUID> {
      let projectIDs = sidebarProjectIDs(in: sidebarProjects)
      var seen = Set<UUID>()
      var duplicates = Set<UUID>()

      for projectID in projectIDs {
        if !seen.insert(projectID).inserted {
          duplicates.insert(projectID)
        }
      }
      return duplicates
    }

    static func hasPhase0Blocker(in sidebarProjects: [WorkspaceSidebarProjectItem]) -> Bool {
      !missingProjectIDNodeIDs(in: sidebarProjects).isEmpty
        || !duplicateVisibleProjectIDs(in: sidebarProjects).isEmpty
    }

    static func timelineInputProjectIDs(
      timelineOrderedProjectIDs: [UUID],
      sidebarProjects: [WorkspaceSidebarProjectItem]
    ) -> Set<UUID> {
      Set(
        timelineInputProjectIDsInOrder(
          timelineOrderedProjectIDs: timelineOrderedProjectIDs,
          sidebarProjects: sidebarProjects
        )
      )
    }

    static func timelineInputProjectIDsInOrder(
      timelineOrderedProjectIDs: [UUID],
      sidebarProjects: [WorkspaceSidebarProjectItem]
    ) -> [UUID] {
      let timelineProjectIDSet = Set(timelineOrderedProjectIDs)
      let sidebarOrderedProjectIDs = sidebarProjectIDs(in: sidebarProjects)
        .filter { timelineProjectIDSet.contains($0) }
      let orderedProjectIDs: [UUID]
      if !sidebarOrderedProjectIDs.isEmpty,
        Set(timelineOrderedProjectIDs).isSubset(of: Set(sidebarOrderedProjectIDs))
      {
        orderedProjectIDs = sidebarOrderedProjectIDs
      } else {
        orderedProjectIDs = timelineOrderedProjectIDs
      }

      var seen = Set<UUID>()
      var normalizedProjectIDs: [UUID] = []

      for projectID in orderedProjectIDs where seen.insert(projectID).inserted {
        normalizedProjectIDs.append(projectID)
      }

      for projectID in timelineOrderedProjectIDs where seen.insert(projectID).inserted {
        normalizedProjectIDs.append(projectID)
      }

      return normalizedProjectIDs
    }

    static func scheduleInputProjectIDs(
      timelineOrderedProjectIDs: [UUID],
      sidebarProjects: [WorkspaceSidebarProjectItem]
    ) -> Set<UUID> {
      timelineInputProjectIDs(
        timelineOrderedProjectIDs: timelineOrderedProjectIDs,
        sidebarProjects: sidebarProjects
      )
    }

    static func coveredProjectIDs(
      in sidebarProjects: [WorkspaceSidebarProjectItem]
    ) -> Set<UUID> {
      Set(sidebarProjectIDs(in: sidebarProjects))
    }

    static func visibleProjectIDs(
      orderedProjectIDs: [UUID],
      sidebarProjects: [WorkspaceSidebarProjectItem]
    ) -> [UUID] {
      let coveredProjectIDs = coveredProjectIDs(in: sidebarProjects)
      guard !coveredProjectIDs.isEmpty else { return orderedProjectIDs }
      return orderedProjectIDs.filter { coveredProjectIDs.contains($0) }
    }

    static func orderedProjectIDs(
      descriptors: [WorkspaceProjectDescriptor],
      filterToken: String,
      mode: ProjectListSortMode
    ) -> [UUID] {
      let normalizedToken = filterToken.trimmingCharacters(in: .whitespacesAndNewlines)
      let visibleDescriptors = descriptors.filter { descriptor in
        guard !descriptor.isArchived else { return false }
        guard !normalizedToken.isEmpty else { return true }
        return matchesSearch(descriptor.title, token: normalizedToken)
      }

      return orderedDescriptors(visibleDescriptors, mode: mode).map(\.id)
    }

    static func activeQuickAddDescriptors(
      descriptors: [WorkspaceProjectDescriptor],
      projectIDs: [UUID]
    ) -> [WorkspaceProjectDescriptor] {
      let descriptorsByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
      return projectIDs.compactMap { projectID in
        guard let descriptor = descriptorsByID[projectID],
          !descriptor.isArchived,
          !descriptor.reminderListIdentifier.isEmpty
        else {
          return nil
        }
        return descriptor
      }
    }

    static func quickAddProjectIDs(
      _ projectIDs: [UUID],
      hiddenProjectIDs: Set<UUID>,
      showsHiddenProjects: Bool
    ) -> [UUID] {
      var seen = Set<UUID>()
      return projectIDs.filter { projectID in
        guard seen.insert(projectID).inserted else { return false }
        return showsHiddenProjects || !hiddenProjectIDs.contains(projectID)
      }
    }

    static func menuProjectIDsInTimelineListOrder(
      timelineVisibleOrder: [UUID],
      fallbackProjectIDs: [UUID]
    ) -> [UUID] {
      let fallbackSet = Set(fallbackProjectIDs)
      var seen = Set<UUID>()
      var ordered = timelineVisibleOrder.filter { projectID in
        fallbackSet.contains(projectID) && seen.insert(projectID).inserted
      }
      ordered.append(
        contentsOf: fallbackProjectIDs.filter { projectID in
          seen.insert(projectID).inserted
        }
      )
      return ordered
    }

    private static func orderedDescriptors(
      _ descriptors: [WorkspaceProjectDescriptor],
      mode: ProjectListSortMode
    ) -> [WorkspaceProjectDescriptor] {
      ProjectOrdering.ordered(descriptors, mode: mode)
    }

    private static func matchesSearch(_ source: String, token: String) -> Bool {
      source.range(
        of: token,
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: .autoupdatingCurrent
      ) != nil
    }
  }

  var workspaceProjectDescriptors: [WorkspaceProjectDescriptor] {
    appState.resolvedWorkspaceProjectDescriptors(context: modelContext)
  }

  var workspaceProjectDescriptorsByID: [UUID: WorkspaceProjectDescriptor] {
    Dictionary(uniqueKeysWithValues: workspaceProjectDescriptors.map { ($0.id, $0) })
  }

  var visibleProjectDescriptors: [WorkspaceProjectDescriptor] {
    let token = chromeState.debouncedProjectFilterToken
    return workspaceProjectDescriptors.filter { descriptor in
      guard !descriptor.isArchived else { return false }
      guard !token.isEmpty else { return true }
      return matchesSearch(descriptor.title, token: token)
    }
  }

  var orderedVisibleProjectDescriptors: [WorkspaceProjectDescriptor] {
    chromeState.orderedVisibleProjectDescriptors(
      descriptors: visibleProjectDescriptors,
      mode: projectListSortMode,
      boardRevision: projectBoardOrderRevision
    )
  }

  var orderedVisibleProjectIDs: [UUID] {
    WorkspaceProjectReadPath.orderedProjectIDs(
      descriptors: workspaceProjectDescriptors,
      filterToken: chromeState.debouncedProjectFilterToken,
      mode: projectListSortMode
    )
  }

  var workspaceFilteredProjectIDs: [UUID] {
    WorkspaceProjectReadPath.visibleProjectIDs(
      orderedProjectIDs: orderedVisibleProjectIDs,
      sidebarProjects: filteredSidebarProjects
    )
  }

  var sidebarRootProjectIDs: [UUID] {
    WorkspaceProjectReadPath.orderedProjectIDs(
      descriptors: workspaceProjectDescriptors,
      filterToken: "",
      mode: projectListSortMode
    )
  }

  var filteredSidebarProjects: [WorkspaceSidebarProjectItem] {
    let token = chromeState.debouncedProjectFilterToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      return workspaceSidebarProjects
    }

    return workspaceSidebarProjects.filter {
      matchesSearch($0.title, token: token)
        || matchesSearch($0.breadcrumbText, token: token)
    }
  }

  func timelineProjectIDs(from visibleProjectIDs: [UUID]) -> [UUID] {
    return WorkspaceProjectReadPath.timelineInputProjectIDsInOrder(
      timelineOrderedProjectIDs: visibleProjectIDs,
      sidebarProjects: filteredSidebarProjects
    )
  }

  var workspaceQuickAddProjectIDs: [UUID] {
    let fallbackProjectIDs = timelineProjectIDs(from: workspaceFilteredProjectIDs)
    let timelineListProjectIDs = WorkspaceProjectReadPath.menuProjectIDsInTimelineListOrder(
      timelineVisibleOrder: appState.timelineProjectListVisibleOrder,
      fallbackProjectIDs: fallbackProjectIDs
    )
    return WorkspaceProjectReadPath.quickAddProjectIDs(
      timelineListProjectIDs,
      hiddenProjectIDs: hiddenTimelineProjectIDs,
      showsHiddenProjects: timelineShowsHiddenProjectLists
    )
  }

  var activeQuickAddProjects: [WorkspaceProjectDescriptor] {
    WorkspaceProjectReadPath.activeQuickAddDescriptors(
      descriptors: workspaceProjectDescriptors,
      projectIDs: workspaceQuickAddProjectIDs
    )
  }

  var syncQuickAddProjects: [WorkspaceQuickAddProjectOption] {
    activeQuickAddProjects.map {
      WorkspaceQuickAddProjectOption(id: $0.id, title: $0.title)
    }
  }

  var syncQuickAddProjectID: UUID? {
    if let defaultCalendarIdentifier = appState.defaultReminderCalendarIdentifier,
      let defaultProject = activeQuickAddProjects.first(where: {
        $0.reminderListIdentifier == defaultCalendarIdentifier
      })
    {
      return defaultProject.id
    }

    if let selectedProjectID = appState.selectedProjectID,
      let selectedProject = activeQuickAddProjects.first(where: { $0.id == selectedProjectID })
    {
      return selectedProject.id
    }

    return activeQuickAddProjects.first?.id
  }

  var workspaceSearchResults: [WorkspaceSearchResult] {
    WorkspaceSearchService.sorted(results: workspaceOnlySearchResults)
  }

  let inspectorFixedWidth: CGFloat = projectDetailEmbeddedFixedWidth
  let workspaceTaskEditPanelWidth: CGFloat = 484
  let workspaceSearchFieldIdealWidth: CGFloat = 320
  let workspaceSearchFieldMinWidth: CGFloat = 36
  let workspaceSearchPanelWidth: CGFloat = 430
  let workspaceSearchPanelMaxHeight: CGFloat = 360
  let workspaceSearchPanelOffset: CGFloat = 6
  static let mainPaneCoordinateSpaceName = "workspaceMainPane"
  static let sidebarProjectListSortModeKey = WorkspaceUserDefaultsKey.sidebarProjectListSortMode
  static let timelineProjectListSortModeKey = WorkspaceUserDefaultsKey.timelineProjectListSortMode

  var projectListSortMode: ProjectListSortMode {
    get {
      ProjectListSortMode.resolved(
        storedRawValue: projectListSortModeRaw,
        primaryKey: Self.sidebarProjectListSortModeKey
      )
    }
    nonmutating set {
      let normalized = newValue == .bucketGrouped ? ProjectListSortMode.priority : newValue
      projectListSortModeRaw = normalized.rawValue
    }
  }

  var timelineProjectListSortMode: ProjectListSortMode {
    get {
      ProjectListSortMode.resolvedTimeline(storedRawValue: timelineProjectListSortModeRaw)
    }
    nonmutating set {
      let normalized = newValue == .bucketGrouped ? ProjectListSortMode.priority : newValue
      timelineProjectListSortModeRaw = ProjectListSortMode.resolvedTimeline(
        storedRawValue: normalized.rawValue
      ).rawValue
    }
  }

  var canInteractivelyReorderProjects: Bool {
    projectListSortMode.allowsInteractiveReordering
  }

  var canInteractivelyReorderSidebarProjects: Bool {
    canInteractivelyReorderProjects
      && !workspaceProjectDescriptors.isEmpty
      && filteredSidebarProjects.count == sidebarRootProjectIDs.count
      && filteredSidebarProjects.allSatisfy { $0.depth == 0 }
  }

  var projectFilterBinding: Binding<String> {
    Binding(
      get: { appState.searchText },
      set: { appState.updateSearchText($0) }
    )
  }

  var showArchive: Bool {
    get { false }
    nonmutating set { _ = newValue }
  }

  func selectProjectContext(_ projectID: UUID?) {
    appState.selectedProjectID = projectID
  }

  func presentEmbeddedProjectDetail(for projectID: UUID) {
    showArchive = false
    selectProjectContext(projectID)
    inspectorSelection = projectID
  }

  func openProjectPage(for projectID: UUID, fallbackTitle: String? = nil) {
    showArchive = false
    selectProjectContext(projectID)
    inspectorSelection = nil

    Task { @MainActor in
      do {
        try await ObsidianTaskOpenService.openProjectNote(
          vaultRootURL: appState.obsidianVaultRootURL,
          projectID: projectID,
          documentOpener: appState.platformUIFoundation.documentOpener
        )
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
    _ = fallbackTitle
  }

  func openProjectTaskInSource(projectID: UUID, taskID: UUID) {
    showArchive = false
    selectProjectContext(projectID)
    inspectorSelection = nil

    Task { @MainActor in
      do {
        try await RemindersAppOpenService.openTask(taskID: taskID)
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  func presentInspector(for projectID: UUID) {
    openProjectPage(for: projectID)
  }

  func workspaceSelectionContainsProject(_ projectID: UUID?) -> Bool {
    guard let projectID else { return false }
    return appState.selectedProjectID == projectID
  }

  var shouldDimNonInspectorUI: Bool {
    inspectorSelection != nil && !showArchive
  }

  @MainActor
  func refreshWorkspaceRuntimeProjectionSnapshotFromSourceIfNeeded() async {
    let projectIDs = appState.resolvedRuntimeProjectionProjectIDs()
    if projectIDs.isEmpty { return }
    _ = await appState.recomputeCachedRuntimeProjectionProjects(projectIDs)
  }

  var workspacePresentationMotionContext: MotionContext {
    MotionContext(
      tier: .presentation,
      isTyping: appState.isEditorActive
    )
  }

  var workspacePresentationMotionQuality: MotionQuality {
    MotionSystem.quality(for: workspacePresentationMotionContext)
  }

  var workspacePanelTransitionAnimation: Animation? {
    MotionSystem.animation(
      for: .panelSlide,
      quality: workspacePresentationMotionQuality
    )
  }

  var workspacePresentationCardStyle: OverlaySurfaceStyle {
    OverlaySurfaceStyle.card(quality: workspacePresentationMotionQuality)
  }

  var workspaceLightweightPresentationStyle: OverlaySurfaceStyle {
    OverlaySurfaceStyle.lightweight(quality: workspacePresentationMotionQuality)
  }

  func timelineOverlayMotionContext(isHovering: Bool) -> MotionContext {
    MotionContext(
      tier: .overlay,
      isTyping: appState.isEditorActive,
      isHovering: isHovering
    )
  }

  func timelineOverlayStyle(isHovering: Bool) -> OverlaySurfaceStyle {
    OverlaySurfaceStyle.card(
      quality: MotionSystem.quality(for: timelineOverlayMotionContext(isHovering: isHovering))
    )
  }

  func timelineOverlayPresentationAnimation(isHovering: Bool) -> Animation? {
    MotionSystem.animation(
      for: .overlayFade,
      quality: MotionSystem.quality(for: timelineOverlayMotionContext(isHovering: isHovering))
    )
  }

  private var workspaceShellSnapshot: WorkspaceShellSnapshot {
    let searchResults = workspaceSearchResults
    let selectedSearchResult =
      searchResults.indices.contains(chromeState.selectedWorkspaceSearchResultIndex)
      ? searchResults[chromeState.selectedWorkspaceSearchResultIndex]
      : nil
    let isSearchPanelVisible =
      chromeState.workspaceSearchFocused
      && !chromeState.workspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let filteredSidebarProjectIDs = workspaceFilteredProjectIDs

    return WorkspaceShellSnapshot(
      filteredProjectIDs: filteredSidebarProjectIDs,
      filteredSidebarProjectIDs: filteredSidebarProjectIDs,
      searchResults: searchResults,
      searchResultIDs: searchResults.map(\.id),
      selectedSearchResult: selectedSearchResult,
      isSearchPanelVisible: isSearchPanelVisible
    )
  }

  var body: some View {
    workspaceRoot
  }

  private var workspaceRoot: some View {
    let snapshot = workspaceShellSnapshot

    return workspaceTransientUISection(snapshot: snapshot)
  }

  private func workspaceTransientUISection(snapshot: WorkspaceShellSnapshot) -> some View {
    workspaceLifecycleSection(snapshot: snapshot)
      .confirmationDialog(
        "프로젝트를 완전히 삭제할까요?",
        isPresented: pendingProjectDeleteDialogBinding,
        titleVisibility: .visible
      ) {
        Button("삭제", role: .destructive) {
          guard let target = pendingPermanentDeleteProject else { return }
          performPermanentDelete(target.id)
          pendingPermanentDeleteProject = nil
        }
        Button("취소", role: .cancel) {
          pendingPermanentDeleteProject = nil
        }
      } message: {
        Text("'\(pendingPermanentDeleteProject?.title ?? "")' 프로젝트와 모든 할일/첨부를 완전히 삭제합니다.")
      }
      .alert("Reminders 동기화", isPresented: $showInitialSyncAlert) {
        Button("동의하고 시작") {
          appState.acceptInitialSyncConsentAndStart()
        }
        Button("지금은 안 함", role: .cancel) {
          appState.setInitialSyncConsentPreference(granted: false)
        }
      } message: {
        Text("앱을 사용하기 위해 Apple Reminders와 동기화를 시작합니다. 기존 데이터가 앱에 반영될 수 있습니다.")
      }
  }

  private func workspaceLifecycleSection(snapshot: WorkspaceShellSnapshot) -> some View {
    workspaceDecoratedRootSection(snapshot: snapshot)
      .task(id: sidebarRootProjectIDs) {
        await reloadWorkspaceSidebarProjects()
      }
      .onChange(of: snapshot.filteredSidebarProjectIDs) { _, projectIDs in
        if let inspectorSelection, !projectIDs.contains(inspectorSelection) {
          dismissInspectorSelection()
        }
        if let projectID = activeWorkspaceProjectListPanelProjectID,
          !projectIDs.contains(projectID)
        {
          dismissWorkspaceProjectListPanel()
        }
      }
      .onChange(of: showArchive) { _, isShowingArchive in
        if isShowingArchive {
          dismissInspectorSelection()
        }
      }
      .onAppear {
#if DEBUG
        WorkspaceLayoutDiagnostics.resetLog()
#endif
        Task { @MainActor in
          await refreshWorkspaceRuntimeProjectionSnapshotFromSourceIfNeeded()
        }
        installLocalKeyMonitor()
        chromeState.syncBoardLoadingState(isLoaded: appState.boardsLoaded, currentMode: appState.viewMode)
        chromeState.refreshProjectFilterImmediately(from: appState.searchText)
        chromeState.refreshWorkspaceSearchImmediately()
        migrateTimelineSortModeToReminderOrderIfNeeded()
        appState.requestStartupSyncIfNeeded()
        presentInitialSyncAlertIfNeeded()
      }
      .onDisappear {
        removeLocalKeyMonitor()
        chromeState.cancelPendingTasks()
      }
      .onChange(of: appState.searchText) { _, newValue in
        chromeState.scheduleProjectFilterDebounce(for: newValue)
      }
      .onChange(of: chromeState.workspaceSearchQuery) { _, newValue in
        chromeState.scheduleWorkspaceSearchDebounce(for: newValue)
      }
      .onChange(of: chromeState.debouncedWorkspaceSearchQuery) { _, _ in
        chromeState.resetWorkspaceSearchSelection()
      }
      .task(id: workspaceSearchReloadSignature) {
        await reloadWorkspaceOnlySearchResults()
      }
      .onChange(of: snapshot.searchResultIDs) { _, ids in
        chromeState.clampWorkspaceSearchSelection(resultCount: ids.count)
      }
      .onChange(of: appState.modelContainer != nil) { _, hasContainer in
        if hasContainer {
          appState.requestStartupSyncIfNeeded()
          presentInitialSyncAlertIfNeeded()
        }
      }
      .onChange(of: appState.boardsLoaded) { _, isLoaded in
        chromeState.syncBoardLoadingState(isLoaded: isLoaded, currentMode: appState.viewMode)
      }
      .onChange(of: appState.viewMode) { _, newMode in
        guard appState.boardsLoaded else { return }
        chromeState.syncBoardLoadingState(isLoaded: true, currentMode: newMode)
      }
      .onReceive(
        NotificationCenter.default.publisher(for: .reminderAppFocusWorkspaceSearchRequested)
      ) { _ in
        focusWorkspaceSearch()
      }
  }

  private func migrateTimelineSortModeToReminderOrderIfNeeded() {
    let defaults = UserDefaults.standard
    let migrationKey = WorkspaceUserDefaultsKey.timelineProjectListSortModeReminderOrderMigration
    guard !defaults.bool(forKey: migrationKey) else { return }
    timelineProjectListSortMode = .manual
    defaults.set(true, forKey: migrationKey)
  }

  private func workspaceDecoratedRootSection(snapshot: WorkspaceShellSnapshot) -> some View {
    workspaceDebugProbeSection(snapshot: snapshot)
      .workspaceHiddenWindowToolbarBackground()
      .background {
        WorkspaceChromeRepairHook()
          .frame(width: 0, height: 0)
      }
      .ignoresSafeArea(.container, edges: .top)
  }

  @ViewBuilder
  private func workspaceDebugProbeSection(snapshot: WorkspaceShellSnapshot) -> some View {
#if DEBUG
    workspaceShellSection(snapshot: snapshot)
      .background(
        WorkspaceLayoutProbe(
          role: .root,
          reason: inspectorSelection == nil ? "inspectorHidden" : "inspectorVisible"
        )
      )
#else
    workspaceShellSection(snapshot: snapshot)
#endif
  }

  private func workspaceShellSection(snapshot: WorkspaceShellSnapshot) -> some View {
    ZStack(alignment: .topLeading) {
      Color.clear
        .ignoresSafeArea()

      workspaceNavigationShellSection(snapshot: snapshot)
      workspaceOverlaySection
    }
  }

  @MainActor
  private func reloadWorkspaceSidebarProjects() async {
    await refreshWorkspaceRuntimeProjectionSnapshotFromSourceIfNeeded()
    let descriptorsByProjectID = Dictionary(
      uniqueKeysWithValues: workspaceProjectDescriptors.map { ($0.id, $0) }
    )
    let reloadedProjects = sidebarRootProjectIDs.compactMap { projectID -> WorkspaceSidebarProjectItem? in
      guard let descriptor = descriptorsByProjectID[projectID] else { return nil }
      return WorkspaceSidebarProjectItem(
        handle: WorkspaceSidebarProjectHandle(nodeID: descriptor.id),
        projectID: descriptor.id,
        title: descriptor.title,
        colorHex: descriptor.colorHex,
        breadcrumbText: "",
        depth: 0
      )
    }
    guard reloadedProjects != workspaceSidebarProjects else { return }
    workspaceSidebarProjects = reloadedProjects
  }

  private func matchesSearch(_ source: String, token: String) -> Bool {
    source.range(
      of: token,
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: .autoupdatingCurrent
    ) != nil
  }

  private var workspaceSearchReloadSignature: String {
    let sidebarSignature = workspaceSidebarProjects
      .map {
        "\($0.nodeID.uuidString):\($0.title):\($0.breadcrumbText)"
      }
      .joined(separator: "|")
    let vaultSignature = appState.obsidianVaultRootURL?.path ?? ""
    return "\(chromeState.debouncedWorkspaceSearchQuery)|\(appState.workspaceTreeRevision)|\(vaultSignature)|\(sidebarSignature)"
  }

  @MainActor
  private func reloadWorkspaceOnlySearchResults() async {
    let query = chromeState.debouncedWorkspaceSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      if !workspaceOnlySearchResults.isEmpty {
        workspaceOnlySearchResults = []
      }
      return
    }

    let workspaceItems = workspaceSidebarProjects
    guard !workspaceItems.isEmpty else {
      if !workspaceOnlySearchResults.isEmpty {
        workspaceOnlySearchResults = []
      }
      return
    }

    let projectResults = WorkspaceSearchService.projectResults(from: workspaceItems, rawQuery: query)
    let projectIDs = workspaceItems.compactMap(\.projectID)
    let taskResults: [WorkspaceSearchResult]
    if projectIDs.isEmpty {
      taskResults = []
    } else {
      let retainedResult = await RetainedWorkspaceSurfaceProjectionBuilder.load(
        obsidianVaultRootURL: appState.obsidianVaultRootURL,
        projectIDs: projectIDs
      )
      let resolvedRead = RetainedWorkspaceSurfaceProjectionBuilder.resolveRetainedOnly(retainedResult)
      taskResults = WorkspaceSearchService.taskResults(
        projectSnapshots: resolvedRead.projectSnapshots,
        scheduleEntriesByProjectID: resolvedRead.scheduleEntriesByProjectID,
        rawQuery: query
      )
    }
    let searchResults = projectResults + taskResults
    guard searchResults != workspaceOnlySearchResults else { return }
    workspaceOnlySearchResults = searchResults
  }

  private func hasVisiblePopoverWindow() -> Bool {
    NSApp.windows.contains { window in
      guard window.isVisible else { return false }
      return String(describing: type(of: window)).localizedCaseInsensitiveContains("popover")
    }
  }
}
