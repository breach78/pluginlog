import SwiftData
import SwiftUI

enum ProjectDetailCompletedVisibilityStore {
  static let defaultHidesCompleted = true

  static func storageKey(for scope: String) -> String {
    "projectDetail.hideCompleted.\(scope)"
  }

  static func hidesCompleted(
    for scope: String,
    userDefaults: UserDefaults = .standard
  ) -> Bool {
    let key = storageKey(for: scope)
    guard userDefaults.object(forKey: key) != nil else {
      return defaultHidesCompleted
    }
    return userDefaults.bool(forKey: key)
  }

  static func setHidesCompleted(
    _ hidesCompleted: Bool,
    for scope: String,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(hidesCompleted, forKey: storageKey(for: scope))
  }
}

private struct ProjectDetailOutlinePendingProjectArchive {
  let title: String
}

private struct ProjectDetailOutlinePendingProjectDeletion {
  let title: String
}

private enum ProjectDetailOutlineFadeMetrics {
  static let internalTopFadeHeight: CGFloat = 0
  static let contentMaskHeight: CGFloat = 112
}

struct ProjectDetailOutlineView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.modelContext) private var modelContext

  let projectID: UUID
  let completedVisibilityStorageScope: String
  let fixedWidth: CGFloat?
  let showsLeadingDivider: Bool
  let registersWorkspaceEscapeHandler: Bool
  let onRequestDetach: (() -> Void)?
  let onRequestClose: (() -> Void)?

  @State private var pendingProjectArchive: ProjectDetailOutlinePendingProjectArchive?
  @State private var pendingProjectDeletion: ProjectDetailOutlinePendingProjectDeletion?
  @State private var workspaceEscapeHandlerID = UUID()
  @State private var hidesCompletedTasks: Bool

  init(
    projectID: UUID,
    completedVisibilityStorageScope: String,
    fixedWidth: CGFloat?,
    showsLeadingDivider: Bool,
    registersWorkspaceEscapeHandler: Bool,
    onRequestDetach: (() -> Void)?,
    onRequestClose: (() -> Void)?
  ) {
    self.projectID = projectID
    self.completedVisibilityStorageScope = completedVisibilityStorageScope
    self.fixedWidth = fixedWidth
    self.showsLeadingDivider = showsLeadingDivider
    self.registersWorkspaceEscapeHandler = registersWorkspaceEscapeHandler
    self.onRequestDetach = onRequestDetach
    self.onRequestClose = onRequestClose
    _hidesCompletedTasks = State(
      initialValue: ProjectDetailCompletedVisibilityStore.hidesCompleted(
        for: completedVisibilityStorageScope
      )
    )
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      detailContent

      if showsWindowControls {
        VStack(alignment: .trailing, spacing: 8) {
          ProjectDetailHeaderControlRail(
            onArchiveProject: requestProjectArchive,
            onDeleteProject: requestProjectDeletion,
            onDetach: onRequestDetach,
            onClose: onRequestClose
          )

          ProjectDetailFloatingControlButton(
            systemName: hidesCompletedTasks ? "eye.slash" : "eye",
            action: { hidesCompletedTasks.toggle() }
          )
          .help(hidesCompletedTasks ? "완료 항목 보기" : "완료 항목 숨기기")
        }
        .padding(.top, 12)
        .padding(.trailing, 24)
        .offset(y: -20)
        .fixedSize()
        .zIndex(10)
      }
    }
    .frame(width: fixedWidth)
    .frame(maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .overlay(alignment: .leading) {
      if showsLeadingDivider {
        Rectangle()
          .fill(Color.secondary.opacity(0.12))
          .frame(width: 1)
      }
    }
    .alert(
      "프로젝트 아카이브",
      isPresented: projectArchivePresentedBinding,
      presenting: pendingProjectArchive
    ) { archive in
      Button("아카이브", role: .destructive) {
        archiveProject(archive)
      }
      .keyboardShortcut(.defaultAction)
      Button("취소", role: .cancel) {}
    } message: { archive in
      Text("'\(archive.title)' 프로젝트를 아카이브할까요?")
    }
    .alert(
      "프로젝트 삭제",
      isPresented: projectDeletionPresentedBinding,
      presenting: pendingProjectDeletion
    ) { deletion in
      Button("삭제", role: .destructive) {
        deleteProject(deletion)
      }
      .keyboardShortcut(.defaultAction)
      Button("취소", role: .cancel) {}
    } message: { deletion in
      Text("'\(deletion.title)' 프로젝트와 모든 할일/첨부를 완전히 삭제할까요?")
    }
    .onAppear {
      registerWorkspaceEscapeHandlerIfNeeded()
    }
    .onChange(of: hidesCompletedTasks) { _, newValue in
      ProjectDetailCompletedVisibilityStore.setHidesCompleted(
        newValue,
        for: completedVisibilityStorageScope
      )
    }
    .onDisappear {
      unregisterWorkspaceEscapeHandlerIfNeeded()
    }
  }

  private var detailContent: some View {
    OutlinerView(
      preferredProjectID: projectID,
      showsTaskAccessoryBand: false,
      hideCompleted: $hidesCompletedTasks,
      topFadeHeight: ProjectDetailOutlineFadeMetrics.internalTopFadeHeight,
      usesIntrinsicProjectHeadingFadeMask: false
    )
    .environmentObject(appState)
    .compositingGroup()
    .mask(alignment: .top) {
      VStack(spacing: 0) {
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0),
            .init(color: .black.opacity(0.9), location: 0.72),
            .init(color: .black, location: 1)
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: ProjectDetailOutlineFadeMetrics.contentMaskHeight)

        Rectangle()
          .fill(Color.black)
      }
    }
  }

  private var showsWindowControls: Bool {
    true
  }

  private func requestProjectArchive() {
    pendingProjectArchive = ProjectDetailOutlinePendingProjectArchive(
      title: resolvedProjectTitle()
    )
  }

  private func requestProjectDeletion() {
    pendingProjectDeletion = ProjectDetailOutlinePendingProjectDeletion(
      title: resolvedProjectTitle()
    )
  }

  private func resolvedProjectTitle() -> String {
    appState.resolvedProjectTitle(forProjectID: projectID, context: modelContext)
  }

  private func archiveProject(_ archive: ProjectDetailOutlinePendingProjectArchive) {
    pendingProjectArchive = nil
    Task { @MainActor in
      let didArchive = await appState.archiveProject(projectID, context: modelContext)
      if didArchive {
        onRequestClose?()
      }
    }
  }

  private func deleteProject(_ deletion: ProjectDetailOutlinePendingProjectDeletion) {
    pendingProjectDeletion = nil
    Task { @MainActor in
      let didDelete = await appState.deleteProjectPermanently(projectID, context: modelContext)
      if didDelete {
        onRequestClose?()
      }
    }
  }

  private func registerWorkspaceEscapeHandlerIfNeeded() {
    guard registersWorkspaceEscapeHandler else { return }
    let handlerID = workspaceEscapeHandlerID
    appState.registerWorkspaceProjectDetailEscapeHandler(id: handlerID) {
      handleProjectDetailEscape()
    }
  }

  private func unregisterWorkspaceEscapeHandlerIfNeeded() {
    guard registersWorkspaceEscapeHandler else { return }
    appState.unregisterWorkspaceProjectDetailEscapeHandler(id: workspaceEscapeHandlerID)
  }

  @discardableResult
  private func handleProjectDetailEscape() -> Bool {
    if pendingProjectArchive != nil {
      pendingProjectArchive = nil
      return true
    }

    if pendingProjectDeletion != nil {
      pendingProjectDeletion = nil
      return true
    }

    if let onRequestClose {
      onRequestClose()
      return true
    }

    return false
  }

  private var projectArchivePresentedBinding: Binding<Bool> {
    Binding(
      get: { pendingProjectArchive != nil },
      set: { isPresented in
        if !isPresented {
          pendingProjectArchive = nil
        }
      }
    )
  }

  private var projectDeletionPresentedBinding: Binding<Bool> {
    Binding(
      get: { pendingProjectDeletion != nil },
      set: { isPresented in
        if !isPresented {
          pendingProjectDeletion = nil
        }
      }
    )
  }
}
