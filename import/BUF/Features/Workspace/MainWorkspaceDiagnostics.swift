import AppKit
import Foundation
import SwiftUI

#if DEBUG
enum WorkspaceLayoutProbeRole: String {
  case root
  case inspector
  case inspectorContent
}

@MainActor
enum WorkspaceLayoutDiagnostics {
  private static let fileURL: URL = {
    let documentsURL =
      FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let directoryURL = documentsURL
      .appendingPathComponent("brainunfog", isDirectory: true)
      .appendingPathComponent("diagnostics", isDirectory: true)
    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL.appendingPathComponent("workspace-layout.log", isDirectory: false)
  }()

  private static let queue = DispatchQueue(label: "BUF.workspace-layout-diagnostics")

  static func resetLog() {
    let fileURL = Self.fileURL
    queue.async {
      try? "".write(to: fileURL, atomically: true, encoding: .utf8)
    }
  }

  static func write(_ message: String) {
    let formatter = ISO8601DateFormatter()
    let timestamp = formatter.string(from: .now)
    let line = "[\(timestamp)] \(message)\n"
    let fileURL = Self.fileURL
    AppLogger.ui.info("\(line, privacy: .public)")
    queue.async {
      let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
      try? (existing + line).write(to: fileURL, atomically: true, encoding: .utf8)
    }
  }

  static func logSnapshot(
    role: WorkspaceLayoutProbeRole,
    reason: String,
    markerView: NSView
  ) {
    guard let window = markerView.window else {
      write("role=\(role.rawValue) reason=\(reason) window=nil")
      return
    }

    let windowFrame = rectString(window.frame)
    let contentLayoutRect = rectString(window.contentLayoutRect)
    let contentViewFrame = rectString(window.contentView?.frame ?? .zero)
    let markerInWindow = rectString(markerView.convert(markerView.bounds, to: nil))
    let markerFrame = rectString(markerView.frame)
    let markerSafeArea = edgeInsetsString(markerView.safeAreaInsets)
    let styleMask = window.styleMask.rawValue
    let titlebarTransparent = window.titlebarAppearsTransparent
    let separatorStyle: String
    if #available(macOS 11.0, *) {
      separatorStyle = "\(window.titlebarSeparatorStyle.rawValue)"
    } else {
      separatorStyle = "n/a"
    }

    let toolbarStyle: String
    if #available(macOS 11.0, *) {
      toolbarStyle = "\(window.toolbarStyle.rawValue)"
    } else {
      toolbarStyle = "n/a"
    }
    let toolbarBaselineSeparator = "\(window.toolbar?.showsBaselineSeparator ?? false)"
    let toolbarVisible = "\(window.toolbar?.isVisible ?? false)"
    let contentBorderTop = String(format: "%.1f", window.contentBorderThickness(for: .maxY))
    let contentBorderBottom = String(format: "%.1f", window.contentBorderThickness(for: .minY))
    let autoBorderTop = "\(window.autorecalculatesContentBorderThickness(for: .maxY))"
    let autoBorderBottom = "\(window.autorecalculatesContentBorderThickness(for: .minY))"

    var segments: [String] = [
      "role=\(role.rawValue)",
      "reason=\(reason)",
      "windowFrame=\(windowFrame)",
      "contentLayoutRect=\(contentLayoutRect)",
      "contentViewFrame=\(contentViewFrame)",
      "markerFrame=\(markerFrame)",
      "markerInWindow=\(markerInWindow)",
      "markerSafeArea=\(markerSafeArea)",
      "styleMask=\(styleMask)",
      "titlebarAppearsTransparent=\(titlebarTransparent)",
      "titlebarSeparatorStyle=\(separatorStyle)",
      "toolbarStyle=\(toolbarStyle)",
      "toolbarVisible=\(toolbarVisible)",
      "toolbarBaselineSeparator=\(toolbarBaselineSeparator)",
      "contentBorderTop=\(contentBorderTop)",
      "contentBorderBottom=\(contentBorderBottom)",
      "autoBorderTop=\(autoBorderTop)",
      "autoBorderBottom=\(autoBorderBottom)",
    ]

    if let scrollView = enclosingScrollView(for: markerView) {
      segments.append("scrollFrame=\(rectString(scrollView.frame))")
      segments.append("scrollBounds=\(rectString(scrollView.bounds))")
      segments.append("scrollAutoInsets=\(scrollView.automaticallyAdjustsContentInsets)")
      segments.append("scrollInsets=\(edgeInsetsString(scrollView.contentInsets))")
      segments.append("scrollScrollerInsets=\(edgeInsetsString(scrollView.scrollerInsets))")
      let clipView = scrollView.contentView
      segments.append("clipFrame=\(rectString(clipView.frame))")
      segments.append("clipBounds=\(rectString(clipView.bounds))")
      segments.append("clipAutoInsets=\(clipView.automaticallyAdjustsContentInsets)")
      segments.append("clipInsets=\(edgeInsetsString(clipView.contentInsets))")
    } else {
      segments.append("scrollView=nil")
    }

    segments.append("superviewChain=\(superviewChain(for: markerView))")
    if role == .root, let themeFrame = window.contentView?.superview {
      segments.append("themeSubviews=\(interestingSubviewSummary(of: themeFrame))")
      segments.append("themeHierarchy=\(descendantHierarchySummary(of: themeFrame, maxDepth: 4))")
      if let titlebarContainer: NSView = firstSubview(namedFragment: "titlebarcontainer", in: themeFrame) {
        segments.append(
          "titlebarHierarchy=\(descendantHierarchySummary(of: titlebarContainer, maxDepth: 5))"
        )
      }
      if let visualEffect: NSView = firstSubview(namedFragment: "visualeffect", in: themeFrame) {
        segments.append(
          "visualEffectHierarchy=\(descendantHierarchySummary(of: visualEffect, maxDepth: 5))"
        )
      }
    }
    write(segments.joined(separator: " | "))
  }

  private static func rectString(_ rect: CGRect) -> String {
    String(
      format: "{x:%.1f,y:%.1f,w:%.1f,h:%.1f}",
      rect.origin.x,
      rect.origin.y,
      rect.size.width,
      rect.size.height
    )
  }

  private static func edgeInsetsString(_ insets: NSEdgeInsets) -> String {
    String(
      format: "{t:%.1f,l:%.1f,b:%.1f,r:%.1f}",
      insets.top,
      insets.left,
      insets.bottom,
      insets.right
    )
  }

  private static func enclosingScrollView(for view: NSView) -> NSScrollView? {
    var current: NSView? = view
    while let node = current {
      if let scrollView = node as? NSScrollView {
        return scrollView
      }
      current = node.superview
    }
    return nil
  }

  private static func superviewChain(for view: NSView) -> String {
    var names: [String] = []
    var current: NSView? = view
    while let node = current {
      names.append(String(describing: type(of: node)))
      current = node.superview
    }
    return names.joined(separator: " -> ")
  }

  private static func interestingSubviewSummary(of root: NSView) -> String {
    let interesting = root.subviews.filter { view in
      let name = String(describing: type(of: view))
      return name.localizedCaseInsensitiveContains("titlebar")
        || name.localizedCaseInsensitiveContains("toolbar")
        || name.localizedCaseInsensitiveContains("separator")
        || name.localizedCaseInsensitiveContains("theme")
        || name.localizedCaseInsensitiveContains("visual")
    }

    guard !interesting.isEmpty else { return "[]" }

    return interesting.map { view in
      let name = String(describing: type(of: view))
      let frame = rectString(view.frame)
      return "\(name){frame=\(frame),hidden=\(view.isHidden),alpha=\(String(format: "%.2f", view.alphaValue))}"
    }
    .joined(separator: ";")
  }

  private static func descendantHierarchySummary(
    of root: NSView,
    maxDepth: Int = 5
  ) -> String {
    var segments: [String] = []

    func walk(_ view: NSView, depth: Int) {
      guard depth <= maxDepth else { return }
      let name = String(describing: type(of: view))
      let frame = rectString(view.frame)
      let descriptor =
        "\(String(repeating: ">", count: depth))\(name){frame=\(frame),hidden=\(view.isHidden),alpha=\(String(format: "%.2f", view.alphaValue)),subviews=\(view.subviews.count)}"
      segments.append(descriptor)
      for child in view.subviews {
        walk(child, depth: depth + 1)
      }
    }

    walk(root, depth: 0)
    return segments.joined(separator: ";")
  }

  private static func firstSubview<T: NSView>(
    namedFragment fragment: String,
    in root: NSView
  ) -> T? {
    for child in root.subviews {
      let name = String(describing: type(of: child))
      if name.localizedCaseInsensitiveContains(fragment), let typed = child as? T {
        return typed
      }
      if let match: T = firstSubview(namedFragment: fragment, in: child) {
        return match
      }
    }
    return nil
  }
}

struct WorkspaceLayoutProbe: NSViewRepresentable {
  let role: WorkspaceLayoutProbeRole
  let reason: String

  func makeNSView(context: Context) -> ProbeView {
    let view = ProbeView()
    view.role = role
    view.reason = reason
    return view
  }

  func updateNSView(_ nsView: ProbeView, context: Context) {
    nsView.role = role
    nsView.reason = reason
    nsView.scheduleSnapshot(reason: "update:\(reason)")
  }

  final class ProbeView: NSView {
    var role: WorkspaceLayoutProbeRole = .root
    var reason: String = "initial"
    private weak var observedWindow: NSWindow?
    private var snapshotScheduled = false

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      installObserversIfNeeded()
      scheduleSnapshot(reason: "viewDidMoveToWindow")
      DispatchQueue.main.async { [weak self] in
        self?.scheduleSnapshot(reason: "nextRunloop")
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
        self?.scheduleSnapshot(reason: "after120ms")
      }
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      scheduleSnapshot(reason: "viewDidMoveToSuperview")
    }

    override func layout() {
      super.layout()
      scheduleSnapshot(reason: "layout")
    }

    private func installObserversIfNeeded() {
      guard let window, observedWindow !== window else { return }
      observedWindow = window
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleWindowDidResize),
        name: NSWindow.didResizeNotification,
        object: window
      )
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleWindowDidEndLiveResize),
        name: NSWindow.didEndLiveResizeNotification,
        object: window
      )
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if let observedWindow {
        NotificationCenter.default.removeObserver(
          self,
          name: NSWindow.didResizeNotification,
          object: observedWindow
        )
        NotificationCenter.default.removeObserver(
          self,
          name: NSWindow.didEndLiveResizeNotification,
          object: observedWindow
        )
      }
      observedWindow = nil
      super.viewWillMove(toWindow: newWindow)
    }

    @objc
    private func handleWindowDidResize() {
      scheduleSnapshot(reason: "windowDidResize")
    }

    @objc
    private func handleWindowDidEndLiveResize() {
      scheduleSnapshot(reason: "windowDidEndLiveResize")
    }

    func scheduleSnapshot(reason: String) {
      guard !snapshotScheduled else { return }
      snapshotScheduled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.snapshotScheduled = false
        WorkspaceLayoutDiagnostics.logSnapshot(role: self.role, reason: reason, markerView: self)
      }
    }
  }
}
#endif

@MainActor
enum WorkspaceChromeRepair {
  private static let trafficLightOffset = CGSize(width: 10, height: 10)
  private static let standardWindowButtonTypes: [NSWindow.ButtonType] = [
    .closeButton,
    .miniaturizeButton,
    .zoomButton,
  ]
  private static var standardWindowButtonBaseFrames: [ObjectIdentifier: CGRect] = [:]

  static func adjustWindowChrome(from markerView: NSView?) {
    guard let window = markerView?.window else { return }

    for buttonType in standardWindowButtonTypes {
      guard let button = window.standardWindowButton(buttonType) else { continue }
      let baseFrame = standardWindowButtonBaseFrame(for: button)
      let yOffset =
        button.superview?.isFlipped == true
        ? trafficLightOffset.height
        : -trafficLightOffset.height
      let targetOrigin = CGPoint(
        x: baseFrame.minX + trafficLightOffset.width,
        y: baseFrame.minY + yOffset
      )

      if abs(button.frame.minX - targetOrigin.x) > 0.5
        || abs(button.frame.minY - targetOrigin.y) > 0.5
      {
        button.setFrameOrigin(targetOrigin)
      }
    }
  }

  static func installZeroInsetInspectorClipView(from markerView: NSView?) {
    guard let scrollView = enclosingScrollView(for: markerView) else { return }
    let zeroInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    if let clipView = scrollView.contentView as? WorkspaceInspectorZeroInsetClipView {
      scrollView.automaticallyAdjustsContentInsets = false
      scrollView.contentInsets = zeroInsets
      scrollView.scrollerInsets = zeroInsets
      clipView.automaticallyAdjustsContentInsets = false
      clipView.contentInsets = zeroInsets
      return
    }

    let existingClipView = scrollView.contentView
    let documentView = scrollView.documentView
    let replacementClipView = WorkspaceInspectorZeroInsetClipView(frame: existingClipView.frame)
    replacementClipView.drawsBackground = existingClipView.drawsBackground
    replacementClipView.backgroundColor = existingClipView.backgroundColor

    scrollView.contentView = replacementClipView
    if let documentView {
      scrollView.documentView = documentView
    }

    scrollView.automaticallyAdjustsContentInsets = false
    scrollView.contentInsets = zeroInsets
    scrollView.scrollerInsets = zeroInsets

    let clipView = scrollView.contentView
    clipView.automaticallyAdjustsContentInsets = false
    clipView.contentInsets = zeroInsets

    let currentOrigin = clipView.bounds.origin
    if currentOrigin.x.isFinite, currentOrigin.y.isFinite, abs(currentOrigin.y) > 0.5 {
      clipView.setBoundsOrigin(CGPoint(x: currentOrigin.x, y: 0))
      scrollView.reflectScrolledClipView(clipView)
    }
  }

  private static func enclosingScrollView(for view: NSView?) -> NSScrollView? {
    var current = view
    while let node = current {
      if let scrollView = node as? NSScrollView {
        return scrollView
      }
      current = node.superview
    }
    return nil
  }

  private static func standardWindowButtonBaseFrame(for button: NSButton) -> CGRect {
    let buttonID = ObjectIdentifier(button)
    if let baseFrame = standardWindowButtonBaseFrames[buttonID] {
      return baseFrame
    }
    standardWindowButtonBaseFrames[buttonID] = button.frame
    return button.frame
  }
}

struct WorkspaceChromeRepairHook: NSViewRepresentable {
  func makeNSView(context: Context) -> RepairView {
    RepairView(mode: .windowChrome)
  }

  func updateNSView(_ nsView: RepairView, context: Context) {
    nsView.scheduleApply()
  }
}

struct WorkspaceInspectorScrollRepairHook: NSViewRepresentable {
  func makeNSView(context: Context) -> RepairView {
    RepairView(mode: .inspectorScroll)
  }

  func updateNSView(_ nsView: RepairView, context: Context) {
    nsView.scheduleApply()
  }
}

final class RepairView: NSView {
  enum Mode {
    case windowChrome
    case inspectorScroll
  }

  private let mode: Mode
  private weak var observedWindow: NSWindow?
  private var applyScheduled = false

  init(mode: Mode) {
    self.mode = mode
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    installObserversIfNeeded()
    scheduleApply()
    DispatchQueue.main.async { [weak self] in
      self?.scheduleApply()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
      self?.scheduleApply()
    }
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    scheduleApply()
  }

  override func layout() {
    super.layout()
    scheduleApply()
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if let observedWindow {
      NotificationCenter.default.removeObserver(
        self,
        name: NSWindow.didResizeNotification,
        object: observedWindow
      )
      NotificationCenter.default.removeObserver(
        self,
        name: NSWindow.didEndLiveResizeNotification,
        object: observedWindow
      )
    }
    observedWindow = nil
    super.viewWillMove(toWindow: newWindow)
  }

  private func installObserversIfNeeded() {
    guard let window, observedWindow !== window else { return }
    observedWindow = window
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWindowResize),
      name: NSWindow.didResizeNotification,
      object: window
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWindowResize),
      name: NSWindow.didEndLiveResizeNotification,
      object: window
    )
  }

  @objc
  private func handleWindowResize() {
    scheduleApply()
  }

  func scheduleApply() {
    guard !applyScheduled else { return }
    applyScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.applyScheduled = false
      self.applyRepair()
    }
  }

  private func applyRepair() {
    switch mode {
    case .windowChrome:
      WorkspaceChromeRepair.adjustWindowChrome(from: self)
    case .inspectorScroll:
      WorkspaceChromeRepair.installZeroInsetInspectorClipView(from: self)
    }
  }
}

final class WorkspaceInspectorZeroInsetClipView: NSClipView {
  override var safeAreaInsets: NSEdgeInsets {
    NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    automaticallyAdjustsContentInsets = false
    contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  }

  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var constrained = super.constrainBoundsRect(proposedBounds)
    if constrained.origin.y.isFinite, constrained.origin.y < 0 {
      constrained.origin.y = 0
    }
    return constrained
  }
}

extension View {
  @ViewBuilder
  func workspaceHiddenWindowToolbarBackground() -> some View {
    if #available(macOS 15.0, *) {
      self.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    } else {
      self
    }
  }
}
