import Foundation
import UniformTypeIdentifiers
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(AppKit)
import AppKit
import ObjectiveC
#endif
#if canImport(UIKit)
import UIKit
#endif

enum PlatformUIFoundationError: LocalizedError {
  case unsupportedPlatform
  case failedToOpenURL
  case failedToLoadDragPayload

  var errorDescription: String? {
    switch self {
    case .unsupportedPlatform:
      return "현재 플랫폼에서 지원되지 않는 UI 작업입니다."
    case .failedToOpenURL:
      return "외부 문서를 열지 못했습니다."
    case .failedToLoadDragPayload:
      return "드래그 데이터를 불러오지 못했습니다."
    }
  }
}

struct PlatformTextSelection: Equatable, Sendable {
  var location: Int
  var length: Int
}

enum PlatformTextEditorFocusReason: String, Equatable, Sendable {
  case programmatic
  case directSelection
  case tabTraversal
  case restore
}

struct PlatformTextEditorFocusRequest: Equatable, Sendable {
  var editorID: String
  var reason: PlatformTextEditorFocusReason
  var issuedAt: Date
}

enum AppInputTypography {
  static let regularFontName = "SansMonoCJKFinalDraft"
  static let boldFontName = "SansMonoCJKFinalDraft-Bold"

  static var defaultPointSize: CGFloat {
    #if canImport(AppKit)
      NSFont.systemFontSize
    #else
      13
    #endif
  }

  #if canImport(AppKit)
    static func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
      let fontName = preferredFontName(weight: weight)
      return NSFont(name: fontName, size: size)
        ?? fallbackNSFont(size: size, weight: weight)
    }

    private static func preferredFontName(weight: NSFont.Weight) -> String {
      weight.rawValue >= NSFont.Weight.semibold.rawValue ? boldFontName : regularFontName
    }

    private static func fallbackNSFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
      weight.rawValue >= NSFont.Weight.semibold.rawValue
        ? .boldSystemFont(ofSize: size)
        : .systemFont(ofSize: size)
    }
  #endif

  #if canImport(SwiftUI)
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
      Font.custom(preferredFontName(weight: weight), size: size)
    }

    private static func preferredFontName(weight: Font.Weight) -> String {
      switch weight {
      case .bold, .semibold, .heavy, .black:
        return boldFontName
      default:
        return regularFontName
      }
    }
  #endif
}

enum NoteFontSelection: String, CaseIterable, Identifiable {
  case savedAppFont
  case appleSDGothicNeo

  var id: String { rawValue }

  var menuTitle: String {
    switch self {
    case .savedAppFont:
      return "현재 저장 폰트"
    case .appleSDGothicNeo:
      return "Apple SD Gothic Neo"
    }
  }
}

enum AppleSDGothicNeoTypography {
  #if canImport(AppKit)
    static func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
      for fontName in fontCandidates(weight: weight) {
        if let font = NSFont(name: fontName, size: size) {
          return font
        }
      }
      return NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static func fontCandidates(weight: NSFont.Weight) -> [String] {
      if weight.rawValue >= NSFont.Weight.bold.rawValue {
        return ["AppleSDGothicNeo-Bold", "AppleSDGothicNeo-SemiBold"]
      }
      if weight.rawValue >= NSFont.Weight.semibold.rawValue {
        return ["AppleSDGothicNeo-SemiBold", "AppleSDGothicNeo-Bold", "AppleSDGothicNeo-Medium"]
      }
      if weight.rawValue >= NSFont.Weight.medium.rawValue {
        return ["AppleSDGothicNeo-Medium", "AppleSDGothicNeo-Regular"]
      }
      return ["AppleSDGothicNeo-Regular", "AppleSDGothicNeo-Medium"]
    }
  #endif

  #if canImport(SwiftUI)
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
      Font.custom(fontName(weight: weight), size: size)
    }

    private static func fontName(weight: Font.Weight) -> String {
      switch weight {
      case .bold, .heavy, .black:
        return "AppleSDGothicNeo-Bold"
      case .semibold:
        return "AppleSDGothicNeo-SemiBold"
      case .medium:
        return "AppleSDGothicNeo-Medium"
      default:
        return "AppleSDGothicNeo-Regular"
      }
    }
  #endif
}

enum NoteTypography {
  static let selectionStorageKey = "notes.typography.selection"

  static func selectedFontSelection(defaults: UserDefaults = .standard) -> NoteFontSelection {
    guard
      let rawValue = defaults.string(forKey: selectionStorageKey),
      let selection = NoteFontSelection(rawValue: rawValue)
    else {
      return .savedAppFont
    }
    return selection
  }

  #if canImport(AppKit)
    static func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
      switch selectedFontSelection() {
      case .savedAppFont:
        return AppInputTypography.nsFont(size: size, weight: weight)
      case .appleSDGothicNeo:
        return AppleSDGothicNeoTypography.nsFont(size: size, weight: weight)
      }
    }
  #endif

  #if canImport(SwiftUI)
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
      switch selectedFontSelection() {
      case .savedAppFont:
        return AppInputTypography.font(size: size, weight: weight)
      case .appleSDGothicNeo:
        return AppleSDGothicNeoTypography.font(size: size, weight: weight)
      }
    }
  #endif
}

@MainActor
final class PlatformTextEditorCoordinator {
  private var pendingRequests: [String: PlatformTextEditorFocusRequest] = [:]

  func requestFocus(
    editorID: String,
    reason: PlatformTextEditorFocusReason = .programmatic
  ) {
    pendingRequests[editorID] = PlatformTextEditorFocusRequest(
      editorID: editorID,
      reason: reason,
      issuedAt: .now
    )
  }

  func consumeFocusRequest(for editorID: String) -> PlatformTextEditorFocusRequest? {
    pendingRequests.removeValue(forKey: editorID)
  }

  func cancelFocusRequest(for editorID: String) {
    pendingRequests.removeValue(forKey: editorID)
  }
}

enum PlatformPathSelectionKind: Sendable {
  case files
  case directory
}

struct PlatformPathPickerRequest: Sendable {
  var kind: PlatformPathSelectionKind
  var message: String
  var prompt: String = "선택"
  var allowsMultipleSelection: Bool = false
  var allowedContentTypes: [UTType] = []
}

@MainActor
protocol PlatformPathPicking {
  func pick(request: PlatformPathPickerRequest) async throws -> [URL]
}

@MainActor
final class ApplePlatformPathPicker: PlatformPathPicking {
  static let shared = ApplePlatformPathPicker()

  func pick(request: PlatformPathPickerRequest) async throws -> [URL] {
    #if canImport(AppKit)
      let panel = NSOpenPanel()
      panel.message = request.message
      panel.prompt = request.prompt
      panel.canChooseDirectories = request.kind == .directory
      panel.canChooseFiles = request.kind == .files
      panel.allowsMultipleSelection = request.allowsMultipleSelection
      if !request.allowedContentTypes.isEmpty {
        panel.allowedContentTypes = request.allowedContentTypes
      }

      guard panel.runModal() == .OK else { return [] }
      return request.allowsMultipleSelection ? panel.urls : panel.url.map { [$0] } ?? []
    #else
      throw PlatformUIFoundationError.unsupportedPlatform
    #endif
  }
}

@MainActor
protocol PlatformDocumentOpening {
  func open(_ url: URL) throws
  func revealInFiles(_ urls: [URL])
}

@MainActor
final class ApplePlatformDocumentOpener: PlatformDocumentOpening {
  static let shared = ApplePlatformDocumentOpener()

  func open(_ url: URL) throws {
    #if canImport(AppKit)
      guard NSWorkspace.shared.open(url) else {
        throw PlatformUIFoundationError.failedToOpenURL
      }
    #elseif canImport(UIKit)
      UIApplication.shared.open(url, options: [:], completionHandler: nil)
    #else
      throw PlatformUIFoundationError.unsupportedPlatform
    #endif
  }

  func revealInFiles(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    #if canImport(AppKit)
      NSWorkspace.shared.activateFileViewerSelecting(urls)
    #elseif canImport(UIKit)
      if let first = urls.first {
        UIApplication.shared.open(first, options: [:], completionHandler: nil)
      }
    #endif
  }
}

@MainActor
protocol PlatformWindowManaging {
  func activateApp()
  func bringVisibleWindowsToFront(titled title: String?)
  func makeMainWindowKeyAndFront()
  func endEditingInFrontWindow()
}

@MainActor
final class ApplePlatformWindowManager: PlatformWindowManaging {
  static let shared = ApplePlatformWindowManager()

  func activateApp() {
    #if canImport(AppKit)
      NSApp.setActivationPolicy(.regular)
      NSApp.activate(ignoringOtherApps: true)
    #endif
  }

  func bringVisibleWindowsToFront(titled title: String?) {
    #if canImport(AppKit)
      for window in NSApp.windows where window.isVisible {
        if let title {
          window.title = title
        }
        window.makeKeyAndOrderFront(nil)
      }
    #endif
  }

  func makeMainWindowKeyAndFront() {
    #if canImport(AppKit)
      if let window = NSApp.mainWindow ?? NSApp.keyWindow {
        window.makeKeyAndOrderFront(nil)
      }
    #endif
  }

  func endEditingInFrontWindow() {
    #if canImport(AppKit)
      if let window = NSApp.keyWindow ?? NSApp.mainWindow {
        window.endEditing(for: nil)
        window.makeFirstResponder(nil)
      }
    #endif
  }
}

enum PlatformContextActionRole {
  case standard
  case destructive
}

enum PlatformContextActionState {
  case off
  case on
  case mixed
}

struct PlatformContextActionDescriptor: Identifiable {
  let id: UUID
  let title: String
  let isEnabled: Bool
  let role: PlatformContextActionRole
  let state: PlatformContextActionState
  let children: [PlatformContextActionDescriptor]
  let handler: (() -> Void)?
  let isSeparator: Bool

  init(
    id: UUID = UUID(),
    title: String,
    isEnabled: Bool = true,
    role: PlatformContextActionRole = .standard,
    state: PlatformContextActionState = .off,
    children: [PlatformContextActionDescriptor] = [],
    handler: (() -> Void)? = nil,
    isSeparator: Bool = false
  ) {
    self.id = id
    self.title = title
    self.isEnabled = isEnabled
    self.role = role
    self.state = state
    self.children = children
    self.handler = handler
    self.isSeparator = isSeparator
  }

  static func action(
    _ title: String,
    isEnabled: Bool = true,
    role: PlatformContextActionRole = .standard,
    state: PlatformContextActionState = .off,
    handler: @escaping () -> Void
  ) -> PlatformContextActionDescriptor {
    PlatformContextActionDescriptor(
      title: title,
      isEnabled: isEnabled,
      role: role,
      state: state,
      handler: handler
    )
  }

  static func disabled(_ title: String) -> PlatformContextActionDescriptor {
    PlatformContextActionDescriptor(title: title, isEnabled: false)
  }

  static func submenu(
    _ title: String,
    isEnabled: Bool = true,
    children: [PlatformContextActionDescriptor]
  ) -> PlatformContextActionDescriptor {
    PlatformContextActionDescriptor(
      title: title,
      isEnabled: isEnabled,
      children: children
    )
  }

  static func separator() -> PlatformContextActionDescriptor {
    PlatformContextActionDescriptor(title: "", isSeparator: true)
  }
}

#if canImport(AppKit)
@MainActor
final class AppKitContextMenuRenderer {
  static let shared = AppKitContextMenuRenderer()
  private static var retainedActionsKey: UInt8 = 0

  func present(
    _ descriptors: [PlatformContextActionDescriptor],
    with event: NSEvent,
    for view: NSView
  ) {
    NSMenu.popUpContextMenu(makeMenu(from: descriptors), with: event, for: view)
  }

  func makeMenu(from descriptors: [PlatformContextActionDescriptor]) -> NSMenu {
    let menu = NSMenu()
    var retainedActions: [ActionTargetBox] = []
    descriptors.compactMap { makeMenuItem(from: $0, retainedActions: &retainedActions) }.forEach {
      menu.addItem($0)
    }
    objc_setAssociatedObject(
      menu,
      &Self.retainedActionsKey,
      retainedActions,
      .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
    return menu
  }

  private func makeMenuItem(
    from descriptor: PlatformContextActionDescriptor,
    retainedActions: inout [ActionTargetBox]
  ) -> NSMenuItem? {
    if descriptor.isSeparator {
      return .separator()
    }

    if !descriptor.children.isEmpty {
      let item = NSMenuItem(title: descriptor.title, action: nil, keyEquivalent: "")
      item.isEnabled = descriptor.isEnabled
      let submenu = NSMenu(title: descriptor.title)
      descriptor.children.compactMap { makeMenuItem(from: $0, retainedActions: &retainedActions) }
        .forEach { submenu.addItem($0) }
      objc_setAssociatedObject(
        submenu,
        &Self.retainedActionsKey,
        retainedActions,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
      )
      item.submenu = submenu
      return item
    }

    let item = NSMenuItem(title: descriptor.title, action: nil, keyEquivalent: "")
    item.state = descriptor.state.nsControlStateValue
    item.isEnabled = descriptor.isEnabled && descriptor.handler != nil
    if let handler = descriptor.handler {
      let target = ActionTargetBox(handler: handler)
      retainedActions.append(target)
      item.target = target
      item.action = #selector(ActionTargetBox.performAction(_:))
    }
    return item
  }

  private final class ActionTargetBox: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
      self.handler = handler
    }

    @objc func performAction(_ sender: Any?) {
      handler()
    }
  }
}

private extension PlatformContextActionState {
  var nsControlStateValue: NSControl.StateValue {
    switch self {
    case .off:
      return .off
    case .on:
      return .on
    case .mixed:
      return .mixed
    }
  }
}
#endif

struct PlatformDragStringPayload: Equatable, Sendable {
  let string: String
}

struct ApplePlatformDragBridge: Sendable {
  static let shared = ApplePlatformDragBridge()

  func itemProvider(for payload: PlatformDragStringPayload) -> NSItemProvider {
    NSItemProvider(object: payload.string as NSString)
  }

  func decodeTextPayload(from item: NSSecureCoding?) -> String? {
    DragPayloadCodec.decodeTextPayload(from: item)
  }

  func loadPlainText(from provider: NSItemProvider) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let payload = DragPayloadCodec.decodeTextPayload(from: item) else {
          continuation.resume(throwing: PlatformUIFoundationError.failedToLoadDragPayload)
          return
        }
        continuation.resume(returning: payload)
      }
    }
  }

  func materializeFileExport(
    sourceURL: URL,
    displayFilename: String,
    exportID: UUID
  ) throws -> URL {
    let exportRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("BUFDragExports", isDirectory: true)
    let exportDirectory = exportRoot.appendingPathComponent(exportID.uuidString, isDirectory: true)

    try FileManager.default.createDirectory(
      at: exportDirectory,
      withIntermediateDirectories: true
    )

    let exportURL = exportDirectory.appendingPathComponent(displayFilename)
    if FileManager.default.fileExists(atPath: exportURL.path) {
      try FileManager.default.removeItem(at: exportURL)
    }

    do {
      try FileManager.default.linkItem(at: sourceURL, to: exportURL)
    } catch {
      try FileManager.default.copyItem(at: sourceURL, to: exportURL)
    }

    return exportURL
  }
}

@MainActor
final class PlatformUIFoundation {
  static let shared = PlatformUIFoundation()

  let textEditorCoordinator: PlatformTextEditorCoordinator
  let pathPicker: any PlatformPathPicking
  let documentOpener: any PlatformDocumentOpening
  let dragBridge: ApplePlatformDragBridge
  let windowManager: any PlatformWindowManaging
  #if canImport(AppKit)
    let contextMenuRenderer: AppKitContextMenuRenderer
  #endif

  init(
    textEditorCoordinator: PlatformTextEditorCoordinator = PlatformTextEditorCoordinator(),
    pathPicker: any PlatformPathPicking = ApplePlatformPathPicker.shared,
    documentOpener: any PlatformDocumentOpening = ApplePlatformDocumentOpener.shared,
    dragBridge: ApplePlatformDragBridge = .shared,
    windowManager: any PlatformWindowManaging = ApplePlatformWindowManager.shared
  ) {
    self.textEditorCoordinator = textEditorCoordinator
    self.pathPicker = pathPicker
    self.documentOpener = documentOpener
    self.dragBridge = dragBridge
    self.windowManager = windowManager
    #if canImport(AppKit)
      self.contextMenuRenderer = .shared
    #endif
  }
}
