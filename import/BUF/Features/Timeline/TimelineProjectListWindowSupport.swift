import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TimelineProjectListOutsideClickMonitor: NSViewRepresentable {
  let onOutsideMouseDown: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onOutsideMouseDown: onOutsideMouseDown)
  }

  func makeNSView(context: Context) -> NSView {
    let view = MonitorView(frame: .zero)
    view.coordinator = context.coordinator
    context.coordinator.attach(to: view)
    context.coordinator.updateFrame(from: view)
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    context.coordinator.onOutsideMouseDown = onOutsideMouseDown
    context.coordinator.attach(to: view)
    context.coordinator.updateFrame(from: view)
  }

  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
    coordinator.detach()
  }

  final class MonitorView: NSView {
    weak var coordinator: Coordinator?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      coordinator?.updateFrame(from: self)
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      coordinator?.updateFrame(from: self)
    }

    override func layout() {
      super.layout()
      coordinator?.updateFrame(from: self)
    }
  }

  final class Coordinator: NSObject {
    var onOutsideMouseDown: () -> Void
    private weak var view: NSView?
    private weak var observedClipView: NSClipView?
    private var monitor: Any?
    private var windowNumber: Int?
    private var frameInWindow: CGRect = .null

    init(onOutsideMouseDown: @escaping () -> Void) {
      self.onOutsideMouseDown = onOutsideMouseDown
    }

    func attach(to view: NSView) {
      self.view = view
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
        [weak self] event in
        self?.handle(event) ?? event
      }
    }

    @MainActor
    func updateFrame(from view: NSView) {
      windowNumber = view.window?.windowNumber
      frameInWindow = view.convert(view.bounds, to: nil)
      updateScrollBoundsObserver(from: view)
    }

    func detach() {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
      if let observedClipView {
        NotificationCenter.default.removeObserver(
          self,
          name: NSView.boundsDidChangeNotification,
          object: observedClipView
        )
      }
      monitor = nil
      view = nil
      observedClipView = nil
      windowNumber = nil
      frameInWindow = .null
    }

    @MainActor
    private func updateScrollBoundsObserver(from view: NSView) {
      guard let clipView = view.enclosingScrollView?.contentView else { return }
      guard observedClipView !== clipView else { return }
      if let observedClipView {
        NotificationCenter.default.removeObserver(
          self,
          name: NSView.boundsDidChangeNotification,
          object: observedClipView
        )
      }
      observedClipView = clipView
      clipView.postsBoundsChangedNotifications = true
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(scrollBoundsDidChange(_:)),
        name: NSView.boundsDidChangeNotification,
        object: clipView
      )
    }

    @objc
    @MainActor
    private func scrollBoundsDidChange(_: Notification) {
      guard let view else { return }
      updateFrame(from: view)
    }

    private func handle(_ event: NSEvent) -> NSEvent {
      guard let windowNumber, event.windowNumber == windowNumber else {
        return event
      }

      if !frameInWindow.contains(event.locationInWindow) {
        onOutsideMouseDown()
      }
      return event
    }

    deinit {
      detach()
    }
  }
}

private struct TimelineProjectNoteFieldBackground: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(TimelineProjectNoteFieldStyle.backgroundColor)
      )
  }
}

enum TimelineProjectNoteAutoSavePolicy {
  static func normalized(_ text: String) -> String {
    ReminderNoteSourceCodec.normalize(text)
  }

  static func isDirty(currentText: String, committedText: String) -> Bool {
    normalized(currentText) != normalized(committedText)
  }
}

private enum TimelineProjectNoteFieldStyle {
  static let backgroundColor = Color(
    nsColor: NSColor(calibratedWhite: 0.975, alpha: 1)
  )
}

extension View {
  func timelineProjectNoteFieldBackground() -> some View {
    modifier(TimelineProjectNoteFieldBackground())
  }
}

struct TimelineProjectListHiddenDragPreview: View {
  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .accessibilityHidden(true)
  }
}

struct TimelineProjectListNotePreviewText: View {
  let markdown: String
  let presentation: TimelineProjectListPresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      ForEach(renderLines) { line in
        renderedLine(line)
      }
    }
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private func renderedLine(_ line: MarkdownLine) -> some View {
    switch line.kind {
    case .blank:
      Color.clear
        .frame(height: 4)
    case .heading(let level, let text):
      inlineText(text)
        .font(headingFont(level: level))
        .foregroundStyle(Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .listItem(let marker, let text, let level):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(marker)
          .font(bodyFont.monospacedDigit())
          .foregroundStyle(Color.secondary.opacity(0.7))
          .frame(width: 25, alignment: .trailing)
        inlineText(text)
          .font(bodyFont)
          .foregroundStyle(Color.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, CGFloat(level) * 16)
    case .paragraph(let text):
      inlineText(text)
        .font(bodyFont)
        .foregroundStyle(Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func inlineText(_ markdown: String) -> Text {
    guard let attributed = try? AttributedString(
      markdown: markdown,
      options: AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
      )
    ) else {
      return Text(markdown)
    }
    return Text(attributed)
  }

  private var renderLines: [MarkdownLine] {
    markdown
      .components(separatedBy: .newlines)
      .enumerated()
      .map { index, line in MarkdownLine(id: index, rawLine: line) }
  }

  private var bodyFont: Font {
    switch presentation {
    case .window:
      return .system(size: 11)
    case .embedded:
      return AppInputTypography.font(
        size: max(TimelineProjectListContent.embeddedTextSize - 1, 10)
      )
    }
  }

  private func headingFont(level: Int) -> Font {
    let scale: CGFloat
    switch level {
    case 1:
      scale = 1.4
    case 2:
      scale = 1.3
    case 3:
      scale = 1.2
    default:
      scale = 1.08
    }
    switch presentation {
    case .window:
      return .system(size: 11 * scale, weight: .semibold)
    case .embedded:
      let size = max(TimelineProjectListContent.embeddedTextSize - 1, 10) * scale
      return AppInputTypography.font(size: size, weight: .semibold)
    }
  }

  private struct MarkdownLine: Identifiable {
    enum Kind {
      case blank
      case heading(level: Int, text: String)
      case listItem(marker: String, text: String, level: Int)
      case paragraph(String)
    }

    let id: Int
    let kind: Kind

    init(id: Int, rawLine: String) {
      self.id = id
      let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else {
        kind = .blank
        return
      }
      if let heading = Self.heading(from: rawLine) {
        kind = heading
        return
      }
      if let listItem = Self.listItem(from: rawLine) {
        kind = listItem
        return
      }
      kind = .paragraph(rawLine)
    }

    private static func heading(from line: String) -> Kind? {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let level = trimmed.prefix { $0 == "#" }.count
      guard (1...6).contains(level),
        trimmed.dropFirst(level).first == " "
      else {
        return nil
      }
      return .heading(
        level: level,
        text: String(trimmed.dropFirst(level).dropFirst()).trimmingCharacters(in: .whitespaces)
      )
    }

    private static func listItem(from line: String) -> Kind? {
      let leadingSpaces = line.prefix { $0 == " " }.count
      let trimmed = line.dropFirst(leadingSpaces)
      if trimmed.hasPrefix("- ") {
        return .listItem(
          marker: "-",
          text: String(trimmed.dropFirst(2)),
          level: leadingSpaces / 4
        )
      }

      let marker = trimmed.prefix { $0.isNumber || $0 == "." }
      let digits = marker.dropLast()
      guard marker.hasSuffix("."),
        !digits.isEmpty,
        digits.allSatisfy(\.isNumber),
        trimmed.dropFirst(marker.count).first == " "
      else {
        return nil
      }
      return .listItem(
        marker: String(marker),
        text: String(trimmed.dropFirst(marker.count + 1)),
        level: leadingSpaces / 4
      )
    }
  }
}

struct TimelineProjectListTaskDropDelegate: DropDelegate {
  let targetTaskID: UUID
  @Binding var draggingTaskID: UUID?
  @Binding var dropIndicator: TimelineProjectListTaskDropIndicator?
  let onPreviewDrop:
    (_ draggedID: UUID, _ targetID: UUID, _ placement: TimelineProjectDropPlacement) -> Bool
  let onPerformDrop:
    () -> Void

  func validateDrop(info: DropInfo) -> Bool {
    draggingTaskID != nil && !info.itemProviders(for: [UTType.text.identifier]).isEmpty
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard let draggingTaskID, draggingTaskID != targetTaskID else {
      dropIndicator = nil
      return DropProposal(operation: .move)
    }
    let placement: TimelineProjectDropPlacement = info.location.y < 20 ? .before : .after
    let indicator = TimelineProjectListTaskDropIndicator(
      targetTaskID: targetTaskID,
      placement: placement
    )
    if dropIndicator != indicator,
      onPreviewDrop(draggingTaskID, targetTaskID, placement)
    {
      dropIndicator = indicator
    }
    return DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    defer {
      draggingTaskID = nil
      dropIndicator = nil
    }
    guard
      draggingTaskID != nil,
      draggingTaskID != targetTaskID
    else {
      return false
    }
    onPerformDrop()
    return true
  }

  func dropExited(info: DropInfo) {
    if dropIndicator?.targetTaskID == targetTaskID {
      dropIndicator = nil
    }
  }
}
