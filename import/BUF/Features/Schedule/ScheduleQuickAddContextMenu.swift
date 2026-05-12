import AppKit
import SwiftUI

struct ScheduleQuickAddPopoverContent: View {
  let projects: [ScheduleQuickAddProjectOption]
  let onSubmit: (String, UUID) -> Void
  let onCancel: () -> Void

  @State var title: String = ""
  @State var selectedProjectID: UUID?
  @State var isFieldFocused = false

  init(
    projects: [ScheduleQuickAddProjectOption],
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
        .font(.system(size: ScheduleUITokens.Panel.quickAddTitleFontSize, weight: .semibold))

      EscapeAwareTextField(
        text: $title,
        isFocused: $isFieldFocused,
        placeholder: "할일 입력",
        onSubmit: submit,
        onEscape: onCancel
      )
      .frame(height: ScheduleUITokens.Panel.quickAddTextFieldHeight)

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
            .font(.system(size: ScheduleUITokens.Panel.quickAddMenuIconFontSize, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, ScheduleUITokens.Panel.quickAddMenuHorizontalPadding)
        .padding(.vertical, ScheduleUITokens.Panel.quickAddMenuVerticalPadding)
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
    .padding(ScheduleUITokens.Spacing.quickAddContentPadding)
    .frame(width: ScheduleUITokens.Panel.quickAddWidth)
    .onAppear {
      DispatchQueue.main.async {
        isFieldFocused = true
      }
    }
    .onExitCommand {
      onCancel()
    }
  }

  var selectedProjectTitle: String {
    projects.first(where: { $0.id == selectedProjectID })?.title ?? "목록 선택"
  }

  func submit() {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let selectedProjectID else { return }
    onSubmit(trimmed, selectedProjectID)
  }
}

final class ScheduleQuickAddContextMenuView: NSView {
  weak var coordinator: ScheduleQuickAddContextMenuRegion.Coordinator?

  override var isFlipped: Bool { true }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  override func rightMouseDown(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    coordinator?.presentMenu(from: self, event: event, location: location)
  }

  override func mouseDown(with event: NSEvent) {
    guard let coordinator else {
      super.mouseDown(with: event)
      return
    }

    guard coordinator.allowsTimedDragCreation else {
      coordinator.handleBackgroundTap()
      return
    }

    let startLocation = convert(event.locationInWindow, from: nil)
    coordinator.beginTimedDrag(at: startLocation)

    window?.trackEvents(
      matching: [.leftMouseDragged, .leftMouseUp],
      timeout: NSEvent.foreverDuration,
      mode: .eventTracking
    ) { [weak self] trackedEvent, stop in
      guard let self, let trackedEvent else {
        stop.pointee = true
        return
      }

      let location = self.convert(trackedEvent.locationInWindow, from: nil)
      switch trackedEvent.type {
      case .leftMouseDragged:
        coordinator.updateTimedDrag(to: location)
      case .leftMouseUp:
        coordinator.finishTimedDrag(at: location)
        stop.pointee = true
      default:
        break
      }
    }
  }
}

struct ScheduleQuickAddContextMenuRegion: NSViewRepresentable {
  let isAllDayRegion: Bool
  let canCreateTask: Bool
  let projects: [ScheduleQuickAddProjectOption]
  let defaultProjectID: UUID?
  let onCreateTask: (String, UUID, CGPoint, Bool) -> Void
  let onUnavailable: () -> Void
  let onBackgroundTap: (() -> Void)?
  let allowsTimedDragCreation: Bool
  let onTimedDragPreview: ((CGPoint, CGPoint) -> Void)?
  let onTimedDragCommit: ((CGPoint, CGPoint) -> Void)?
  let onTimedDragCancel: (() -> Void)?

  @MainActor
  final class Coordinator: NSObject {
    var isAllDayRegion = false
    var canCreateTask = false
    var projects: [ScheduleQuickAddProjectOption] = []
    var defaultProjectID: UUID?
    var onCreateTask: ((String, UUID, CGPoint, Bool) -> Void)?
    var onUnavailable: (() -> Void)?
    var onBackgroundTap: (() -> Void)?
    var allowsTimedDragCreation = false
    var onTimedDragPreview: ((CGPoint, CGPoint) -> Void)?
    var onTimedDragCommit: ((CGPoint, CGPoint) -> Void)?
    var onTimedDragCancel: (() -> Void)?
    weak var hostView: ScheduleQuickAddContextMenuView?
    var lastLocation: CGPoint = .zero
    var popover: NSPopover?
    var dragStartLocation: CGPoint?
    let dragThreshold: CGFloat = 4

    func presentMenu(from view: ScheduleQuickAddContextMenuView, event: NSEvent, location: CGPoint)
    {
      lastLocation = location
      var descriptors: [PlatformContextActionDescriptor] = [
        .action("할일 추가", isEnabled: canCreateTask) { [weak self] in
          self?.openQuickAddPopover()
        }
      ]

      if !canCreateTask {
        descriptors.append(.disabled("추가할 목록이 없습니다"))
      }

      AppKitContextMenuRenderer.shared.present(descriptors, with: event, for: view)
    }

    @MainActor
    func openQuickAddPopover() {
      guard canCreateTask, let hostView else {
        onUnavailable?()
        return
      }

      popover?.close()

      let popover = NSPopover()
      popover.behavior = .transient
      popover.contentSize = NSSize(width: ScheduleUITokens.Panel.quickAddWidth, height: 134)
      popover.contentViewController = NSHostingController(
        rootView: ScheduleQuickAddPopoverContent(
          projects: projects,
          defaultProjectID: defaultProjectID,
          onSubmit: { [weak self] title, projectID in
            guard let self else { return }
            self.onCreateTask?(title, projectID, self.lastLocation, self.isAllDayRegion)
            self.popover?.close()
            self.popover = nil
          },
          onCancel: { [weak self] in
            self?.popover?.close()
            self?.popover = nil
          }
        )
      )
      popover.show(
        relativeTo: CGRect(x: lastLocation.x, y: lastLocation.y, width: 1, height: 1),
        of: hostView,
        preferredEdge: .maxY
      )
      self.popover = popover
    }

    func beginTimedDrag(at location: CGPoint) {
      guard allowsTimedDragCreation else { return }
      dragStartLocation = location
      onTimedDragCancel?()
    }

    func updateTimedDrag(to location: CGPoint) {
      guard allowsTimedDragCreation, let dragStartLocation else { return }
      if exceedsDragThreshold(from: dragStartLocation, to: location) {
        onTimedDragPreview?(dragStartLocation, location)
      } else {
        onTimedDragCancel?()
      }
    }

    func finishTimedDrag(at location: CGPoint) {
      defer { dragStartLocation = nil }
      guard allowsTimedDragCreation, let dragStartLocation else { return }
      if exceedsDragThreshold(from: dragStartLocation, to: location) {
        onTimedDragCommit?(dragStartLocation, location)
      } else {
        onTimedDragCancel?()
        onBackgroundTap?()
      }
    }

    func handleBackgroundTap() {
      onTimedDragCancel?()
      onBackgroundTap?()
    }

    func exceedsDragThreshold(from start: CGPoint, to end: CGPoint) -> Bool {
      max(abs(end.x - start.x), abs(end.y - start.y)) >= dragThreshold
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> ScheduleQuickAddContextMenuView {
    let view = ScheduleQuickAddContextMenuView()
    view.coordinator = context.coordinator
    context.coordinator.hostView = view
    return view
  }

  func updateNSView(_ nsView: ScheduleQuickAddContextMenuView, context: Context) {
    context.coordinator.hostView = nsView
    context.coordinator.isAllDayRegion = isAllDayRegion
    context.coordinator.canCreateTask = canCreateTask
    context.coordinator.projects = projects
    context.coordinator.defaultProjectID = defaultProjectID
    context.coordinator.onCreateTask = onCreateTask
    context.coordinator.onUnavailable = onUnavailable
    context.coordinator.onBackgroundTap = onBackgroundTap
    context.coordinator.allowsTimedDragCreation = allowsTimedDragCreation
    context.coordinator.onTimedDragPreview = onTimedDragPreview
    context.coordinator.onTimedDragCommit = onTimedDragCommit
    context.coordinator.onTimedDragCancel = onTimedDragCancel
  }
}
