import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSidebarProjectHandle: Hashable, Identifiable {
  let nodeID: UUID

  var id: UUID { nodeID }
}

struct WorkspaceSidebarProjectItem: Identifiable, Equatable {
  let handle: WorkspaceSidebarProjectHandle
  let projectID: UUID?
  let title: String
  let colorHex: String?
  let breadcrumbText: String
  let depth: Int

  var id: WorkspaceSidebarProjectHandle { handle }
  var nodeID: UUID { handle.nodeID }
}

struct LegacySidebarProjectDropModifier: ViewModifier {
  let projectID: UUID?
  @Binding var sidebarTaskDropTargetProjectID: UUID?
  let onPerformTaskDrop: (UUID, UUID) -> Void

  func body(content: Content) -> some View {
    guard let projectID else { return AnyView(content) }
    return AnyView(
      content.onDrop(
        of: [UTType.text.identifier],
        delegate: WorkspaceProjectTaskDropDelegate(
          targetProjectID: projectID,
          taskDropTargetProjectID: $sidebarTaskDropTargetProjectID,
          onPerformTaskDrop: onPerformTaskDrop
        )
      )
    )
  }
}

extension MainWorkspaceView {
  func sidebar() -> some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField("프로젝트 필터", text: projectFilterBinding)
        .textFieldStyle(.roundedBorder)
        .font(AppInputTypography.font(size: AppInputTypography.defaultPointSize))

      HStack(spacing: 8) {
        WorkspaceProjectSortButton(
          sortMode: Binding(
            get: { projectListSortMode },
            set: { projectListSortMode = $0 }
          ),
          context: .sidebar,
          fillsWidth: true
        )

        sidebarAddProjectButton
      }

      List {
        ForEach(filteredSidebarProjects) { project in
          sidebarProjectRow(project)
        }
        .onMove(perform: moveProjects)
        .moveDisabled(
          !canInteractivelyReorderSidebarProjects
            || !appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .listStyle(.sidebar)
    }
    .padding(12)
    .frame(minWidth: 250)
    .sheet(item: $pendingRenameProject) { request in
      WorkspaceRenameProjectSheetContent(
        originalTitle: request.title,
        isRenaming: isRenamingProject,
        onSubmit: { title in
          submitProjectRename(projectID: request.id, title: title)
        },
        onCancel: {
          pendingRenameProject = nil
        }
      )
    }
    .simultaneousGesture(
      TapGesture().onEnded {
        dismissWorkspaceSearchPanel()
      })
  }

  func sidebarProjectRow(_ project: WorkspaceSidebarProjectItem) -> some View {
    let isSelected = workspaceSelectionContainsProject(project.projectID)
    let dropHighlight = project.projectID.flatMap { sidebarTaskDropTargetProjectID == $0 } ?? false
    let backgroundColor =
      dropHighlight ? Color.accentColor.opacity(0.18)
      : isSelected ? Color.accentColor.opacity(0.10)
      : Color.clear

    return Button {
      showArchive = false
      if let projectID = project.projectID {
        presentInspector(for: projectID)
      }
    } label: {
      sidebarProjectLabel(project)
    }
    .buttonStyle(.plain)
    .listRowBackground(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(backgroundColor)
        .padding(.vertical, 1)
    )
    .modifier(
      LegacySidebarProjectDropModifier(
        projectID: project.projectID,
        sidebarTaskDropTargetProjectID: $sidebarTaskDropTargetProjectID,
        onPerformTaskDrop: moveTaskToProjectFromSidebar
      )
    )
    .contextMenu {
      if let projectID = project.projectID {
        Button {
          pendingRenameProject = .init(id: projectID, title: project.title)
        } label: {
          Label("이름 변경", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
          pendingPermanentDeleteProject = .init(id: projectID, title: project.title)
        } label: {
          Label("삭제", systemImage: "trash")
        }
      }
    }
  }

  func sidebarProjectLabel(_ project: WorkspaceSidebarProjectItem) -> some View {
    HStack(alignment: .center, spacing: 8) {
      Circle()
        .fill(ColorHexCodec.color(from: project.colorHex) ?? .blue)
        .frame(width: 8, height: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(project.title)
          .lineLimit(1)

        if !project.breadcrumbText.isEmpty {
          Text(project.breadcrumbText)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.leading, CGFloat(project.depth) * 10)
  }

  var sidebarAddProjectButton: some View {
    Button {
      showSidebarAddProjectPopover = true
    } label: {
      Image(systemName: "plus.circle.fill")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.primary.opacity(0.82))
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .popover(isPresented: $showSidebarAddProjectPopover, arrowEdge: .bottom) {
      WorkspaceNewProjectPopoverContent(
        isCreating: isCreatingSidebarProject,
        onSubmit: submitSidebarNewProject,
        onCancel: {
          showSidebarAddProjectPopover = false
        }
      )
      .overlaySurface(
        cornerRadius: 12,
        strokeColor: .primary,
        style: workspacePresentationCardStyle
      )
    }
    .help("새 프로젝트 생성")
  }

  func submitProjectRename(projectID: UUID, title: String) {
    guard !isRenamingProject else { return }
    isRenamingProject = true
    Task { @MainActor in
      let didRename = await appState.renameProject(
        projectID,
        to: title,
        context: modelContext
      )
      isRenamingProject = false
      if didRename {
        pendingRenameProject = nil
      }
    }
  }
}
