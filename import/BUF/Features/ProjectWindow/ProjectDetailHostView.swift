import SwiftUI

let projectDetailEmbeddedFixedWidth: CGFloat = 700

struct ProjectDetailHostView: View {
  let projectID: UUID
  let completedVisibilityStorageScope: String
  let fixedWidth: CGFloat?
  let showsLeadingDivider: Bool
  let registersWorkspaceEscapeHandler: Bool
  let navigationRequestID: UUID?
  let onScrollRequest: ((UUID, ScrollViewProxy) -> Void)?
  let onRequestDetach: (() -> Void)?
  let onRequestClose: (() -> Void)?

  init(
    projectID: UUID,
    completedVisibilityStorageScope: String = "workspaceInspector",
    fixedWidth: CGFloat? = nil,
    showsLeadingDivider: Bool = false,
    registersWorkspaceEscapeHandler: Bool = false,
    navigationRequestID: UUID? = nil,
    onScrollRequest: ((UUID, ScrollViewProxy) -> Void)? = nil,
    onRequestDetach: (() -> Void)? = nil,
    onRequestClose: (() -> Void)? = nil
  ) {
    self.projectID = projectID
    self.completedVisibilityStorageScope = completedVisibilityStorageScope
    self.fixedWidth = fixedWidth
    self.showsLeadingDivider = showsLeadingDivider
    self.registersWorkspaceEscapeHandler = registersWorkspaceEscapeHandler
    self.navigationRequestID = navigationRequestID
    self.onScrollRequest = onScrollRequest
    self.onRequestDetach = onRequestDetach
    self.onRequestClose = onRequestClose
  }

  var body: some View {
    ProjectDetailOutlineView(
      projectID: projectID,
      completedVisibilityStorageScope: completedVisibilityStorageScope,
      fixedWidth: fixedWidth,
      showsLeadingDivider: showsLeadingDivider,
      registersWorkspaceEscapeHandler: registersWorkspaceEscapeHandler,
      onRequestDetach: onRequestDetach,
      onRequestClose: onRequestClose
    )
  }
}
