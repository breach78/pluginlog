import AppKit
import SwiftUI

extension MainWorkspaceView {
  @ViewBuilder
  func workspaceInspectorReservation(
    selection: UUID?,
    taskEditTarget: WorkspaceTaskEditPanelTarget?
  ) -> some View {
    let isVisible = (selection != nil && !showArchive) || taskEditTarget != nil
    let reservedWidth = taskEditTarget == nil ? inspectorFixedWidth : workspaceTaskEditPanelWidth

    Color.clear
      .frame(width: isVisible ? reservedWidth : 0, alignment: .trailing)
      .contentShape(Rectangle())
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .clipped()
      .animation(workspacePanelTransitionAnimation, value: isVisible)
  }

  @ViewBuilder
  func workspaceInspectorOverlayHost(
    selection: UUID?,
    taskEditTarget: WorkspaceTaskEditPanelTarget?
  ) -> some View {
    let isVisible = (selection != nil && !showArchive) || taskEditTarget != nil

    GeometryReader { _ in
      ZStack(alignment: .topTrailing) {
        if let taskEditTarget {
          workspaceTaskEditPanel(taskEditTarget)
            .zIndex(2)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if let selection, !showArchive {
          inspectorPane(selection: selection)
            .zIndex(1)
            .transition(
              .asymmetric(
                insertion: .offset(x: 18).combined(with: .opacity),
                removal: .offset(x: 18).combined(with: .opacity)
              )
            )
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
    .animation(workspacePanelTransitionAnimation, value: isVisible)
  }

  func workspaceTaskEditPanel(_ target: WorkspaceTaskEditPanelTarget) -> some View {
    TimelineTaskEditPopoverContent(
      initialFields: target.initialFields,
      presentationStyle: .panel,
      vaultRootURL: appState.obsidianVaultRootURL,
      loadFields: {
        await loadTimelineTaskEditFields(
          projectID: target.projectID,
          taskID: target.taskID,
          fallback: target.initialFields
        )
      },
      saveFields: { fields in
        try await saveTimelineTaskEditFields(
          fields,
          projectID: target.projectID,
          taskID: target.taskID
        )
      },
      onCancel: {
        dismissTimelineTaskEditor()
      }
    )
    .id("\(target.projectID.uuidString)-\(target.taskID.uuidString)")
    .frame(width: workspaceTaskEditPanelWidth, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: NSColor(calibratedWhite: 1, alpha: 1)))
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(Color(nsColor: .separatorColor))
        .frame(width: 1)
    }
  }

  @ViewBuilder
  func timelineTaskBadgeOverlayHost(
    _ presentation: TimelineTaskBadgeOverlayPresentation?
  ) -> some View {
    GeometryReader { _ in
      if let presentation {
        timelineTaskBadgeOverlayCard(presentation)
          .offset(x: presentation.frame.minX, y: presentation.frame.minY)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .transition(.offset(y: -3).combined(with: .opacity))
          .zIndex(7)
      }
    }
    .animation(
      timelineOverlayPresentationAnimation(isHovering: appState.isHoveringTimelineTaskBadgeOverlay),
      value: presentation?.frame
    )
  }

  @ViewBuilder
  func timelineDayHeaderOverlayHost(
    _ presentation: TimelineDayHeaderOverlayPresentation?
  ) -> some View {
    GeometryReader { _ in
      if let presentation {
        timelineDayHeaderOverlayCard(presentation)
          .offset(x: presentation.frame.minX, y: presentation.frame.minY)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .transition(.offset(y: -3).combined(with: .opacity))
          .zIndex(7)
      }
    }
    .animation(
      timelineOverlayPresentationAnimation(isHovering: appState.isHoveringTimelineDayHeaderOverlay),
      value: presentation?.frame
    )
  }

  @ViewBuilder
  func inspectorPane(selection: UUID) -> some View {
    Color.clear
      .frame(width: 0, height: 0)
      .onAppear {
        openProjectPage(for: selection)
        dismissInspectorSelection()
      }
#if DEBUG
      .background(WorkspaceLayoutProbe(role: .inspector, reason: "inspectorPane"))
#endif
  }

  @ViewBuilder
  func timelineTaskBadgeOverlayCard(
    _ presentation: TimelineTaskBadgeOverlayPresentation
  ) -> some View {
    let projectColor = timelineOverlayProjectColor(
      for: presentation.projectReference,
      colorHex: presentation.projectColorHex
    )

    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 8) {
        if !presentation.strongTasks.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(presentation.strongTasks) { task in
              HStack(spacing: 8) {
                Button {
                  completeTimelineTask(task.taskID, projectID: presentation.projectReference.id)
                } label: {
                  timelineDayHeaderTaskMarker(
                    isOverdue: task.isOverdue,
                    color: projectColor
                  )
                }
                .buttonStyle(.plain)

                Button {
                  showTimelineTaskEditor(
                    taskID: task.taskID,
                    projectID: presentation.projectReference.id,
                    title: task.title,
                    date: presentation.date
                  )
                } label: {
                  HStack(spacing: 0) {
                    Text(task.title)
                      .font(.system(size: 12))
                      .foregroundStyle(.primary)
                      .lineLimit(1)

                    Spacer(minLength: 0)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }

            if presentation.hiddenStrongCount > 0 {
              Text("+\(presentation.hiddenStrongCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 21)
            }
          }
        }

        if !presentation.lightTasks.isEmpty {
          if !presentation.strongTasks.isEmpty {
            Divider()
          }

          VStack(alignment: .leading, spacing: 6) {
            ForEach(presentation.lightTasks) { task in
              HStack(spacing: 8) {
                Button {
                  completeTimelinePlannedWork(
                    taskID: task.taskID,
                    projectID: presentation.projectReference.id,
                    targetCompletedUnits: task.targetCompletedUnits,
                    completedOn: presentation.date
                  )
                } label: {
                  timelineDayHeaderTaskMarker(
                    isOverdue: false,
                    color: projectColor
                  )
                }
                .buttonStyle(.plain)

                Button {
                  showTimelineTaskEditor(
                    taskID: task.taskID,
                    projectID: presentation.projectReference.id,
                    title: task.title,
                    date: presentation.date
                  )
                } label: {
                  HStack(spacing: 0) {
                    Text(task.title)
                      .font(.system(size: 12))
                      .foregroundStyle(.primary.opacity(0.58))
                      .lineLimit(1)

                    Spacer(minLength: 0)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }

            if presentation.hiddenLightCount > 0 {
              Text("+\(presentation.hiddenLightCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 21)
            }
          }
        }

        if !presentation.completedTasks.isEmpty {
          if !presentation.strongTasks.isEmpty || !presentation.lightTasks.isEmpty {
            Divider()
          }

          VStack(alignment: .leading, spacing: 6) {
            ForEach(presentation.completedTasks) { task in
              Button {
                showTimelineTaskEditor(
                  taskID: task.taskID,
                  projectID: presentation.projectReference.id,
                  title: task.title,
                  date: presentation.date
                )
              } label: {
                HStack(spacing: 8) {
                  timelineDayHeaderCompletedMarker(color: projectColor)

                  Text(task.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                  Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }

            if presentation.hiddenCompletedCount > 0 {
              Text("+\(presentation.hiddenCompletedCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 21)
            }
          }
        }
      }
    }
    .padding(10)
    .frame(width: presentation.frame.width, alignment: .leading)
    .contentShape(RoundedRectangle(cornerRadius: 12))
    .overlaySurface(
      cornerRadius: 12,
      fillColor: Color(nsColor: NSColor(calibratedWhite: 0.985, alpha: 1)),
      strokeColor: .secondary,
      style: timelineOverlayStyle(isHovering: appState.isHoveringTimelineTaskBadgeOverlay)
    )
    .onHover { isHovering in
      if isHovering {
        appState.isHoveringTimelineTaskBadgeOverlay = true
      } else if activeWorkspaceTaskEditPanelTarget == nil {
        appState.isHoveringTimelineTaskBadgeOverlay = false
      }
    }
    .onDisappear {
      if activeWorkspaceTaskEditPanelTarget == nil {
        appState.isHoveringTimelineTaskBadgeOverlay = false
      }
    }
  }

  @ViewBuilder
  func timelineDayHeaderOverlayCard(
    _ presentation: TimelineDayHeaderOverlayPresentation
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(presentation.sections.enumerated()), id: \.element.id) { index, section in
        let sectionColor = timelineOverlayProjectColor(
          for: section.projectReference,
          colorHex: section.projectColorHex
        )

        VStack(alignment: .leading, spacing: 6) {
          Text(section.projectTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(sectionColor)

          ForEach(section.tasks) { task in
            if task.isCompleted {
              Button {
                showTimelineTaskEditor(
                  taskID: task.taskID,
                  projectID: task.projectReference.id,
                  title: task.title,
                  date: presentation.date
                )
              } label: {
                HStack(spacing: 8) {
                  timelineDayHeaderCompletedMarker(color: sectionColor)

                  Text(task.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                  Spacer(minLength: 0)

                  Text("완료")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.9))
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            } else {
              HStack(spacing: 8) {
                Button {
                  completeTimelineTask(task.taskID, projectID: task.projectReference.id)
                } label: {
                  timelineDayHeaderTaskMarker(
                    isOverdue: task.isOverdue,
                    color: sectionColor
                  )
                }
                .buttonStyle(.plain)

                Button {
                  showTimelineTaskEditor(
                    taskID: task.taskID,
                    projectID: task.projectReference.id,
                    title: task.title,
                    date: presentation.date
                  )
                } label: {
                  HStack(spacing: 0) {
                    Text(task.title)
                      .font(.system(size: 12))
                      .foregroundStyle(.primary)
                      .lineLimit(1)

                    Spacer(minLength: 0)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        if index < presentation.sections.count - 1 {
          Divider()
        }
      }
    }
    .padding(10)
    .frame(width: presentation.frame.width, alignment: .topLeading)
    .contentShape(RoundedRectangle(cornerRadius: 12))
    .overlaySurface(
      cornerRadius: 12,
      fillColor: Color(nsColor: NSColor(calibratedWhite: 0.985, alpha: 1)),
      strokeColor: .secondary,
      style: timelineOverlayStyle(isHovering: appState.isHoveringTimelineDayHeaderOverlay)
    )
    .onHover { isHovering in
      if isHovering {
        appState.isHoveringTimelineDayHeaderOverlay = true
      } else if activeWorkspaceTaskEditPanelTarget == nil {
        appState.isHoveringTimelineDayHeaderOverlay = false
      }
    }
    .onDisappear {
      if activeWorkspaceTaskEditPanelTarget == nil {
        appState.isHoveringTimelineDayHeaderOverlay = false
      }
    }
  }

  func timelineOverlayProjectColor(
    for reference: WorkspaceProjectReference,
    colorHex: String?
  ) -> Color {
    ColorHexCodec.color(from: colorHex)
      ?? ColorHexCodec.color(from: workspaceProjectDescriptorsByID[reference.id]?.colorHex)
      ?? .blue
  }

  @ViewBuilder
  func timelineDayHeaderTaskMarker(
    isOverdue: Bool,
    color: Color
  ) -> some View {
    if isOverdue {
      ZStack {
        Image(systemName: "circle")
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(color.opacity(0.96))

        Image(systemName: "arrowtriangle.down.fill")
          .font(.system(size: 5.5, weight: .bold))
          .foregroundStyle(color.opacity(0.96))
          .offset(y: 0.75)
      }
      .frame(width: 20, height: 20)
      .contentShape(Rectangle())
    } else {
      Image(systemName: "circle")
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(color.opacity(0.86))
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }
  }

  func timelineDayHeaderCompletedMarker(color: Color) -> some View {
    Image(systemName: "checkmark.circle.fill")
      .font(.system(size: 13, weight: .regular))
      .foregroundStyle(color.opacity(0.9))
      .frame(width: 20, height: 20)
      .contentShape(Rectangle())
  }

  func scrollInspectorIfNeeded(
    for request: WorkspaceNavigationRequest?,
    projectID: UUID,
    proxy: ScrollViewProxy
  ) {
    guard let request, request.target.projectID == projectID else { return }

    Task { @MainActor in
      let delays: [UInt64] =
        request.target.requiresDeferredScroll
        ? [0, 120_000_000, 280_000_000]
        : [0, 90_000_000]

      for delay in delays {
        if delay > 0 {
          try? await Task.sleep(nanoseconds: delay)
        }

        MotionTransaction.perform(
          .scrollToTarget,
          quality: workspacePresentationMotionQuality
        ) {
          proxy.scrollTo(request.target.scrollAnchorID, anchor: .top)
        }
      }
    }
  }
}
