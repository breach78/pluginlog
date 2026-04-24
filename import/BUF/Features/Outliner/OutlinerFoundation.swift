import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

let outlineMirrorPasteboardType = NSPasteboard.PasteboardType(
  "com.brainunfog.outliner.mirror-reference"
)

@MainActor
enum OutlineSelectionDiagnostics {
  private static let isEnabled = false
  private static let prefix = "[OutlineSelectionDebug]"
  private static let fileURL: URL = {
    let documentsURL =
      FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let directoryURL = documentsURL
      .appendingPathComponent("brainunfog", isDirectory: true)
      .appendingPathComponent("diagnostics", isDirectory: true)
    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL.appendingPathComponent("outline-selection.log", isDirectory: false)
  }()
  private static let queue = DispatchQueue(label: "BUF.outline-selection-diagnostics")

  static func resetLog() {
    guard isEnabled else { return }
    let fileURL = Self.fileURL
    queue.async {
      try? "".write(to: fileURL, atomically: true, encoding: .utf8)
    }
  }

  static func log(_ message: String) {
    guard isEnabled else { return }
    AppLogger.ui.notice("\(prefix, privacy: .public) \(message, privacy: .public)")
    let formatter = ISO8601DateFormatter()
    let line = "[\(formatter.string(from: .now))] \(prefix) \(message)\n"
    if let data = line.data(using: .utf8) {
      try? FileHandle.standardError.write(contentsOf: data)
    }
    let fileURL = Self.fileURL
    queue.async {
      let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
      try? (existing + line).write(to: fileURL, atomically: true, encoding: .utf8)
    }
  }

  static func describeResponder(_ responder: NSResponder?) -> String {
    guard let responder else { return "nil" }
    let typeName = String(describing: type(of: responder))
    if let textView = responder as? NSTextView {
      return "\(typeName)(editable=\(textView.isEditable), selectable=\(textView.isSelectable))"
    }
    if let control = responder as? NSControl {
      return "\(typeName)(currentEditor=\(control.currentEditor() != nil))"
    }
    return typeName
  }

  static func describeModifiers(_ flags: NSEvent.ModifierFlags) -> String {
    let normalized = flags.intersection(.deviceIndependentFlagsMask)
    var parts: [String] = []
    if normalized.contains(.shift) { parts.append("shift") }
    if normalized.contains(.control) { parts.append("control") }
    if normalized.contains(.option) { parts.append("option") }
    if normalized.contains(.command) { parts.append("command") }
    return parts.isEmpty ? "none" : parts.joined(separator: "+")
  }

  static func navigationRelevantModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    let normalized = flags.intersection(.deviceIndependentFlagsMask)
    var relevant: NSEvent.ModifierFlags = []
    if normalized.contains(.shift) { relevant.insert(.shift) }
    if normalized.contains(.control) { relevant.insert(.control) }
    if normalized.contains(.option) { relevant.insert(.option) }
    if normalized.contains(.command) { relevant.insert(.command) }
    return relevant
  }
}

@MainActor
enum OutlineRenderPerformanceDiagnostics {
  private static let isEnabled = false
  private static let prefix = "[OutlineRenderPerf]"

  static func logVisibleProjectionRebuild(entryCount: Int, visibleTreeRootCount: Int) {
    guard isEnabled else { return }
    AppLogger.ui.notice(
      "\(prefix, privacy: .public) projectionRebuild entries=\(entryCount, privacy: .public) roots=\(visibleTreeRootCount, privacy: .public)"
    )
  }

  static func logViewportWindowChange(
    reason: String,
    previousWindow: OutlineVirtualizationWindow,
    nextWindow: OutlineVirtualizationWindow,
    rowCount: Int,
    viewportHeight: CGFloat
  ) {
    guard isEnabled else { return }
    AppLogger.ui.notice(
      """
      \(prefix, privacy: .public) viewportWindowChange reason=\(reason, privacy: .public) \
      previous=[\(previousWindow.startIndex, privacy: .public),\(previousWindow.endIndex, privacy: .public)) \
      next=[\(nextWindow.startIndex, privacy: .public),\(nextWindow.endIndex, privacy: .public)) \
      rows=\(rowCount, privacy: .public) viewportHeight=\(viewportHeight, privacy: .public)
      """
    )
  }
}

enum OutlinerCanvasMetrics {
  static let horizontalPadding: CGFloat = 40
  static let verticalPadding: CGFloat = 30
  static let topFadeHeight: CGFloat = 40
  static let breadcrumbItemSpacing: CGFloat = 4
  static let breadcrumbLineSpacing: CGFloat = 4
  static let breadcrumbMaxTextLength: Int = 36
  static let fontSize: CGFloat = 13
  static let lineSpacing: CGFloat = 12
  static let indentWidth: CGFloat = 68
  static let guideOffset: CGFloat = 24
  static let guideInset: CGFloat = 6
}

enum OutlinerFonts {
  private static let preferredRegularFamily = "SansMonoCJKFinalDraft"
  private static let preferredBoldFamily = "SansMonoCJKFinalDraft-Bold"
  private static let fallbackRegularFamily = "AppleSDGothicNeo-Regular"
  private static let fallbackMediumFamily = "AppleSDGothicNeo-Medium"
  private static let fallbackSemiboldFamily = "AppleSDGothicNeo-SemiBold"
  private static let fallbackBoldFamily = "AppleSDGothicNeo-Bold"
  private static let pointSizeDelta: CGFloat = 2

  static func resolvedSize(_ size: CGFloat) -> CGFloat {
    size + pointSizeDelta
  }

  static func sandoll(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    let resolvedSize = resolvedSize(size)
    guard let fontName = resolvedFontName(for: weight, size: resolvedSize) else {
      return .system(size: resolvedSize, weight: weight)
    }
    return Font.custom(fontName, size: resolvedSize)
  }

  static func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let resolvedSize = resolvedSize(size)
    return resolvedFont(for: weight, size: resolvedSize)
      ?? NSFont.systemFont(ofSize: resolvedSize, weight: weight)
  }

  static func exactNSFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    resolvedFont(for: weight, size: size)
      ?? NSFont.systemFont(ofSize: size, weight: weight)
  }

  private static func resolvedFontName(for weight: Font.Weight, size: CGFloat) -> String? {
    resolvedFontName(candidates: fontCandidates(for: weight), size: size)
  }

  private static func resolvedFontName(for weight: NSFont.Weight, size: CGFloat) -> String? {
    resolvedFontName(candidates: fontCandidates(for: weight), size: size)
  }

  private static func resolvedFontName(candidates: [String], size: CGFloat) -> String? {
    for candidate in candidates where NSFont(name: candidate, size: size) != nil {
      return candidate
    }
    return nil
  }

  private static func resolvedFont(for weight: NSFont.Weight, size: CGFloat) -> NSFont? {
    guard let fontName = resolvedFontName(for: weight, size: size) else { return nil }
    return NSFont(name: fontName, size: size)
  }

  private static func fontCandidates(for weight: Font.Weight) -> [String] {
    switch weight {
    case .black, .heavy, .bold:
      return [preferredBoldFamily, fallbackBoldFamily, fallbackSemiboldFamily]
    case .semibold:
      return [preferredBoldFamily, fallbackSemiboldFamily, fallbackBoldFamily, fallbackMediumFamily]
    case .medium:
      return [preferredRegularFamily, fallbackMediumFamily, fallbackRegularFamily]
    default:
      return [preferredRegularFamily, fallbackRegularFamily, fallbackMediumFamily]
    }
  }

  private static func fontCandidates(for weight: NSFont.Weight) -> [String] {
    switch weight {
    case let value where value >= .bold:
      return [preferredBoldFamily, fallbackBoldFamily, fallbackSemiboldFamily]
    case let value where value >= .semibold:
      return [preferredBoldFamily, fallbackSemiboldFamily, fallbackBoldFamily, fallbackMediumFamily]
    case let value where value >= .medium:
      return [preferredRegularFamily, fallbackMediumFamily, fallbackRegularFamily]
    default:
      return [preferredRegularFamily, fallbackRegularFamily, fallbackMediumFamily]
    }
  }
}

extension Font {
  static func sandoll(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    OutlinerFonts.sandoll(size: size, weight: weight)
  }
}

extension OutlinerTaskSidecarMetadata {
  static let empty = OutlinerTaskSidecarMetadata()

  var hasMeaningfulContent: Bool {
    requiredWorkDays > 0
      || scheduledDurationMinutes != nil
      || !attachmentPreviews.isEmpty
  }
}

extension ReminderMetadataSnapshot {
  static let empty = ReminderMetadataSnapshot()

  var badgeData: OutlineNodeBadgeData {
    OutlineNodeBadgeData(
      dueDate: dueDate,
      hasExplicitTime: hasExplicitTime,
      recurrenceText: recurrence?.displayText,
      priority: priority
    )
  }

  var hasMeaningfulContent: Bool {
    dueDate != nil || completionDate != nil || recurrence != nil || priority > 0
  }
}

extension OutlinerLiveReminderSnapshot {
  var reminderMetadata: ReminderMetadataSnapshot {
    ReminderMetadataSnapshot(
      dueDate: dueDate,
      completionDate: completionDate,
      hasExplicitTime: hasExplicitTime,
      recurrence: recurrence,
      priority: priority
    )
  }
}

enum OutlineRenderProfile {
  case logseqBaseline
  case full

  var showsBadges: Bool {
    switch self {
    case .logseqBaseline:
      false
    case .full:
      true
    }
  }

  var showsAccessoryBand: Bool {
    switch self {
    case .logseqBaseline:
      true
    case .full:
      true
    }
  }

  var showsReferenceSuggestions: Bool {
    switch self {
    case .logseqBaseline:
      false
    case .full:
      true
    }
  }

  var showsBreadcrumbChrome: Bool {
    switch self {
    case .logseqBaseline:
      true
    case .full:
      true
    }
  }

  var usesCloneSpecificMarkers: Bool {
    switch self {
    case .logseqBaseline:
      false
    case .full:
      true
    }
  }
}

enum OutlinerReminderQuickDuePreset: CaseIterable {
  case today
  case tomorrow
  case dayAfterTomorrow

  var title: String {
    switch self {
    case .today:
      return "오늘"
    case .tomorrow:
      return "내일"
    case .dayAfterTomorrow:
      return "모레"
    }
  }

  func resolvedDate(from now: Date = .now, hasExplicitTime: Bool = false) -> Date {
    let calendar = Calendar.autoupdatingCurrent
    let baseDate: Date
    switch self {
    case .today:
      baseDate = now
    case .tomorrow:
      baseDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
    case .dayAfterTomorrow:
      baseDate = calendar.date(byAdding: .day, value: 2, to: now) ?? now
    }

    guard hasExplicitTime else {
      return calendar.startOfDay(for: baseDate)
    }

    let timeComponents = calendar.dateComponents([.hour, .minute], from: now)
    return calendar.date(
      bySettingHour: timeComponents.hour ?? 9,
      minute: timeComponents.minute ?? 0,
      second: 0,
      of: baseDate
    ) ?? baseDate
  }
}

enum OutlinerQuickDueDirective {
  case set(Date, hasExplicitTime: Bool)
  case clear
}

enum OutlinerQuickRecurrenceDirective {
  case set(OutlinerRecurrenceSample)
  case clear
}

enum OutlinerReminderEditorAction {
  case applyDuePreset(OutlinerReminderQuickDuePreset)
  case clearDue
  case setDue(Date, hasExplicitTime: Bool)
  case setRecurrence(OutlinerRecurrenceSample?)
  case cycleRecurrence
  case setPriority(Int)
  case cyclePriority
}

struct OutlinerQuickReminderParseResult {
  let cleanedText: String
  let dueDirective: OutlinerQuickDueDirective?
  let recurrenceDirective: OutlinerQuickRecurrenceDirective?
  let priority: Int?

  var hasMetadataChanges: Bool {
    dueDirective != nil || recurrenceDirective != nil || priority != nil
  }
}

enum OutlinerQuickReminderParser {
  private static let clearDueTokens: Set<String> = ["날짜없음", "마감없음"]

  static func parse(
    text: String,
    existingMetadata: ReminderMetadataSnapshot,
    now: Date = .now
  ) -> OutlinerQuickReminderParseResult {
    let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !tokens.isEmpty else {
      return OutlinerQuickReminderParseResult(
        cleanedText: text,
        dueDirective: nil,
        recurrenceDirective: nil,
        priority: nil
      )
    }

    var cursor = tokens.count
    var parsedPriority: Int?
    var recurrenceDirective: OutlinerQuickRecurrenceDirective?
    var dueDirective: OutlinerQuickDueDirective?

    if let priority = parsePriorityToken(tokens[safe: cursor - 1]) {
      parsedPriority = priority
      cursor -= 1
    }

    if let recurrence = parseRecurrenceToken(tokens[safe: cursor - 1]) {
      recurrenceDirective = recurrence
      cursor -= 1
    }

    let timeTokens = parseTrailingTimeTokens(tokens: tokens, cursor: cursor)
    if timeTokens.tokenCount > 0 {
      cursor -= timeTokens.tokenCount
    }

    if let dateDirective = parseDueToken(
      tokens: tokens,
      cursor: cursor,
      timeMatch: timeTokens,
      existingMetadata: existingMetadata,
      now: now
    ) {
      dueDirective = dateDirective.directive
      cursor -= dateDirective.tokenCount
    }

    return OutlinerQuickReminderParseResult(
      cleanedText: tokens.prefix(cursor).joined(separator: " "),
      dueDirective: dueDirective,
      recurrenceDirective: recurrenceDirective,
      priority: parsedPriority
    )
  }

  private struct ParsedDueDirective {
    let directive: OutlinerQuickDueDirective
    let tokenCount: Int
  }

  private struct TimeMatch {
    let tokenCount: Int
    let hour: Int
    let minute: Int
  }

  private static func parseDueToken(
    tokens: [String],
    cursor: Int,
    timeMatch: TimeMatch,
    existingMetadata: ReminderMetadataSnapshot,
    now: Date
  ) -> ParsedDueDirective? {
    if let token = tokens[safe: cursor - 1], clearDueTokens.contains(token) {
      return ParsedDueDirective(directive: .clear, tokenCount: 1)
    }

    guard let dateToken = tokens[safe: cursor - 1] else {
      if timeMatch.tokenCount > 0, let existingDate = existingMetadata.dueDate {
        return ParsedDueDirective(
          directive: .set(
            applyingTime(hour: timeMatch.hour, minute: timeMatch.minute, to: existingDate),
            hasExplicitTime: true
          ),
          tokenCount: 0
        )
      }
      return nil
    }

    let calendar = Calendar.autoupdatingCurrent
    let baseDate: Date?
    switch dateToken {
    case "오늘":
      baseDate = now
    case "내일":
      baseDate = calendar.date(byAdding: .day, value: 1, to: now)
    case "모레":
      baseDate = calendar.date(byAdding: .day, value: 2, to: now)
    default:
      baseDate = nil
    }

    guard let baseDate else { return nil }

    if timeMatch.tokenCount > 0 {
      return ParsedDueDirective(
        directive: .set(
          applyingTime(hour: timeMatch.hour, minute: timeMatch.minute, to: baseDate),
          hasExplicitTime: true
        ),
        tokenCount: 1
      )
    }

    return ParsedDueDirective(
      directive: .set(calendar.startOfDay(for: baseDate), hasExplicitTime: false),
      tokenCount: 1
    )
  }

  private static func parseTrailingTimeTokens(tokens: [String], cursor: Int) -> TimeMatch {
    guard let lastToken = tokens[safe: cursor - 1] else {
      return TimeMatch(tokenCount: 0, hour: 0, minute: 0)
    }

    let meridiemToken = tokens[safe: cursor - 2]
    if let parsed = parseTimeToken(lastToken, meridiem: meridiemToken) {
      return TimeMatch(
        tokenCount: meridiemToken == "오전" || meridiemToken == "오후" ? 2 : 1,
        hour: parsed.hour,
        minute: parsed.minute
      )
    }

    return TimeMatch(tokenCount: 0, hour: 0, minute: 0)
  }

  private static func parseTimeToken(_ token: String, meridiem: String?) -> (hour: Int, minute: Int)? {
    if token.contains(":") {
      let components = token.split(separator: ":").map(String.init)
      guard components.count == 2,
        let rawHour = Int(components[0]),
        let minute = Int(components[1]),
        (0...23).contains(rawHour),
        (0...59).contains(minute)
      else {
        return nil
      }
      return (normalizedHour(rawHour, meridiem: meridiem), minute)
    }

    let compact = token.replacingOccurrences(of: "분", with: "")
    if compact.hasSuffix("시"),
      let hour = Int(compact.dropLast())
    {
      return (normalizedHour(hour, meridiem: meridiem), 0)
    }

    if let range = compact.range(of: "시"),
      let hour = Int(compact[..<range.lowerBound]),
      let minute = Int(compact[range.upperBound...]),
      (0...59).contains(minute)
    {
      return (normalizedHour(hour, meridiem: meridiem), minute)
    }

    return nil
  }

  private static func normalizedHour(_ hour: Int, meridiem: String?) -> Int {
    guard let meridiem else { return hour }
    switch meridiem {
    case "오전":
      return hour == 12 ? 0 : hour
    case "오후":
      return hour == 12 ? 12 : min(23, hour + 12)
    default:
      return hour
    }
  }

  private static func parseRecurrenceToken(
    _ token: String?
  ) -> OutlinerQuickRecurrenceDirective? {
    guard let token else { return nil }
    switch token {
    case "매일":
      return .set(.daily(interval: 1))
    case "매주":
      return .set(.weekly(interval: 1, weekdays: []))
    case "매월":
      return .set(.monthly(interval: 1))
    case "매년":
      return .set(.yearly(interval: 1))
    case "반복없음":
      return .clear
    default:
      return nil
    }
  }

  private static func parsePriorityToken(_ token: String?) -> Int? {
    guard let token else { return nil }
    switch token.lowercased() {
    case "p0":
      return 0
    case "p1", "중요":
      return 1
    case "p2":
      return 5
    case "p3":
      return 9
    default:
      return nil
    }
  }

  private static func applyingTime(hour: Int, minute: Int, to date: Date) -> Date {
    let calendar = Calendar.autoupdatingCurrent
    return calendar.date(
      bySettingHour: hour,
      minute: minute,
      second: 0,
      of: date
    ) ?? date
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}

struct OutlineNodeSelectionRequest: Equatable {
  let nodeID: UUID
  let cursorPosition: Int
}

struct OutlineVisibleTreeNode: Identifiable {
  let entry: OutlineFlattenedEntry
  let rowIndex: Int
  let rowCount: Int
  let children: [OutlineVisibleTreeNode]

  var id: UUID { entry.id }
}

enum OutlineVirtualizationMetrics {
  static let estimatedRowHeight: CGFloat = OutlineRowLayoutSpec.estimatedRowHeight
  static let overscanRowCount: Int = 24
  static let activationRowCount: Int = 120
}

struct OutlineVirtualizationWindow: Equatable {
  let startIndex: Int
  let endIndex: Int

  static func full(rowCount: Int) -> OutlineVirtualizationWindow {
    OutlineVirtualizationWindow(startIndex: 0, endIndex: rowCount)
  }

  func contains(_ rowIndex: Int) -> Bool {
    rowIndex >= startIndex && rowIndex < endIndex
  }

  func intersects(startIndex candidateStartIndex: Int, rowCount: Int) -> Bool {
    let candidateEndIndex = candidateStartIndex + rowCount
    return candidateStartIndex < endIndex && candidateEndIndex > startIndex
  }

  static func visibleStartIndex(treeMinY: CGFloat) -> Int {
    let rowHeight = max(1, OutlineVirtualizationMetrics.estimatedRowHeight)
    let visibleMinY = max(0, -treeMinY)
    return max(0, Int(floor(visibleMinY / rowHeight)))
  }

  static func resolved(
    rowCount: Int,
    viewportHeight: CGFloat,
    visibleStartIndex: Int
  ) -> OutlineVirtualizationWindow {
    guard rowCount > OutlineVirtualizationMetrics.activationRowCount,
          viewportHeight > 1 else {
      return full(rowCount: rowCount)
    }

    let rowHeight = max(1, OutlineVirtualizationMetrics.estimatedRowHeight)
    let visibleRowCount = max(1, Int(ceil(viewportHeight / rowHeight)))
    let rawStartIndex = visibleStartIndex - OutlineVirtualizationMetrics.overscanRowCount
    let rawEndIndex = visibleStartIndex + visibleRowCount + OutlineVirtualizationMetrics.overscanRowCount
    let startIndex = max(0, rawStartIndex)
    let endIndex = min(rowCount, max(startIndex + 1, rawEndIndex))
    return OutlineVirtualizationWindow(startIndex: startIndex, endIndex: endIndex)
  }

  static func resolved(
    rowCount: Int,
    viewportHeight: CGFloat,
    treeMinY: CGFloat
  ) -> OutlineVirtualizationWindow {
    resolved(
      rowCount: rowCount,
      viewportHeight: viewportHeight,
      visibleStartIndex: visibleStartIndex(treeMinY: treeMinY)
    )
  }
}

@MainActor
final class OutlineLocalKeyMonitor: ObservableObject {
  var token: Any?
}

enum OutlineVirtualizationCoordinateSpace {
  static let viewport = "BUF.Outliner.VirtualizationViewport"
}

struct OutlineVirtualizationViewportHeightPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

struct OutlineVirtualizationTreeMinYPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

struct OutlineMouseHoverTracker: NSViewRepresentable {
  let onHoverChange: (Bool) -> Void

  func makeNSView(context: Context) -> TrackingView {
    let view = TrackingView()
    view.onHoverChange = onHoverChange
    return view
  }

  func updateNSView(_ nsView: TrackingView, context: Context) {
    nsView.onHoverChange = onHoverChange
  }

  static func dismantleNSView(_ nsView: TrackingView, coordinator: ()) {
    nsView.onHoverChange = { _ in }
  }

  final class TrackingView: NSView {
    var onHoverChange: (Bool) -> Void = { _ in }
    private var trackingAreaRef: NSTrackingArea?

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      if let trackingAreaRef {
        removeTrackingArea(trackingAreaRef)
      }
      let trackingAreaRef = NSTrackingArea(
        rect: .zero,
        options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
        owner: self,
        userInfo: nil
      )
      addTrackingArea(trackingAreaRef)
      self.trackingAreaRef = trackingAreaRef
    }

    override func mouseEntered(with event: NSEvent) {
      super.mouseEntered(with: event)
      onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
      super.mouseExited(with: event)
      onHoverChange(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
    }
  }
}

struct OutlineSelectionKeyResponder: NSViewRepresentable {
  let isActive: Bool
  let onEscape: () -> Void
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void
  let onShiftMoveUp: () -> Void
  let onShiftMoveDown: () -> Void

  func makeNSView(context: Context) -> KeyView {
    let view = KeyView()
    view.onEscape = onEscape
    view.onMoveUp = onMoveUp
    view.onMoveDown = onMoveDown
    view.onShiftMoveUp = onShiftMoveUp
    view.onShiftMoveDown = onShiftMoveDown
    view.isActive = isActive
    return view
  }

  func updateNSView(_ nsView: KeyView, context: Context) {
    nsView.onEscape = onEscape
    nsView.onMoveUp = onMoveUp
    nsView.onMoveDown = onMoveDown
    nsView.onShiftMoveUp = onShiftMoveUp
    nsView.onShiftMoveDown = onShiftMoveDown
    nsView.isActive = isActive
    nsView.activateIfNeeded()
  }

  final class KeyView: NSView {
    var isActive = false
    var onEscape: () -> Void = {}
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onShiftMoveUp: () -> Void = {}
    var onShiftMoveDown: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      OutlineSelectionDiagnostics.log(
        "responder.viewDidMoveToWindow window=\(window?.windowNumber ?? -1)"
      )
      activateIfNeeded()
    }

    func activateIfNeeded() {
      guard isActive, let window else { return }
      OutlineSelectionDiagnostics.log(
        "responder.activateIfNeeded firstResponder=\(OutlineSelectionDiagnostics.describeResponder(window.firstResponder))"
      )
      if let textView = window.firstResponder as? NSTextView, textView.isEditable {
        OutlineSelectionDiagnostics.log("responder.activateIfNeeded.skip editableTextView")
        return
      }
      if window.firstResponder !== self {
        DispatchQueue.main.async { [weak self] in
          guard let self, self.isActive, let window = self.window else { return }
          if let textView = window.firstResponder as? NSTextView, textView.isEditable {
            OutlineSelectionDiagnostics.log("responder.activateIfNeeded.asyncSkip editableTextView")
            return
          }
          OutlineSelectionDiagnostics.log(
            "responder.makeFirstResponder previous=\(OutlineSelectionDiagnostics.describeResponder(window.firstResponder))"
          )
          window.makeFirstResponder(self)
        }
      }
    }

    override func keyDown(with event: NSEvent) {
      OutlineSelectionDiagnostics.log(
        "responder.keyDown keyCode=\(event.keyCode) modifiers=\(OutlineSelectionDiagnostics.describeModifiers(event.modifierFlags)) isActive=\(isActive)"
      )
      guard isActive else {
        super.keyDown(with: event)
        return
      }

      let flags = OutlineSelectionDiagnostics.navigationRelevantModifiers(event.modifierFlags)
      switch (event.keyCode, flags) {
      case (53, _):
        onEscape()
      case (126, []):
        onMoveUp()
      case (125, []):
        onMoveDown()
      case (126, .shift):
        onShiftMoveUp()
      case (125, .shift):
        onShiftMoveDown()
      default:
        super.keyDown(with: event)
      }
    }

    override func cancelOperation(_ sender: Any?) {
      guard isActive else {
        super.cancelOperation(sender)
        return
      }
      onEscape()
    }
  }
}

struct OutlineVisibleTreeRenderer<RowContent: View>: View {
  let nodes: [OutlineVisibleTreeNode]
  let visibleWindow: OutlineVirtualizationWindow
  let dropTargetNodeID: UUID?
  let dropPlacement: OutlineNodeDragDropEngine.Placement?
  let updateDropPlacement: (UUID, OutlineNodeDragDropEngine.Placement?) -> Void
  let performDrop: (OutlineNodeIDTransfer, CGPoint, OutlineFlattenedEntry) -> Void
  let rowContent: (OutlineFlattenedEntry) -> RowContent

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(nodes) { node in
        OutlineVisibleTreeNodeView(
          node: node,
          visibleWindow: visibleWindow,
          dropTargetNodeID: dropTargetNodeID,
          dropPlacement: dropPlacement,
          updateDropPlacement: updateDropPlacement,
          performDrop: performDrop,
          rowContent: rowContent
        )
      }
    }
  }
}

struct OutlineNodeRowDropDelegate: DropDelegate {
  let targetEntry: OutlineFlattenedEntry
  let placementResolver: (CGPoint, OutlineFlattenedEntry) -> OutlineNodeDragDropEngine.Placement
  let updatePlacement: (UUID, OutlineNodeDragDropEngine.Placement?) -> Void
  let performDrop: (OutlineNodeIDTransfer, CGPoint, OutlineFlattenedEntry) -> Void

  func validateDrop(info: DropInfo) -> Bool {
    info.hasItemsConforming(to: [UTType.json])
  }

  func dropEntered(info: DropInfo) {
    updateDropPlacement(info)
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    updateDropPlacement(info)
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    updatePlacement(targetEntry.id, nil)
  }

  func performDrop(info: DropInfo) -> Bool {
    updateDropPlacement(info)
    guard let provider = info.itemProviders(for: [UTType.json]).first else {
      updatePlacement(targetEntry.id, nil)
      return false
    }

    let dropLocation = info.location
    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
      guard let data, let transfer = try? JSONDecoder().decode(OutlineNodeIDTransfer.self, from: data)
      else {
        DispatchQueue.main.async {
          updatePlacement(targetEntry.id, nil)
        }
        return
      }

      DispatchQueue.main.async {
        performDrop(transfer, dropLocation, targetEntry)
      }
    }

    return true
  }

  private func updateDropPlacement(_ info: DropInfo) {
    let placement = placementResolver(info.location, targetEntry)
    updatePlacement(targetEntry.id, placement)
  }
}

func outlineDropIndicatorLeadingInset(
  depth: Int,
  placement: OutlineNodeDragDropEngine.Placement
) -> CGFloat {
  let _ = depth
  switch placement {
  case .child:
    return OutlineRowLayoutSpec.indentWidth + OutlineRowLayoutSpec.controlSlotWidth
  case .above, .below:
    return OutlineRowLayoutSpec.controlSlotWidth
  }
}

struct OutlineNodeDropSlot: View {
  let targetEntry: OutlineFlattenedEntry
  let activePlacement: OutlineNodeDragDropEngine.Placement?
  let placementResolver: (CGPoint, OutlineFlattenedEntry) -> OutlineNodeDragDropEngine.Placement
  let updatePlacement: (UUID, OutlineNodeDragDropEngine.Placement?) -> Void
  let performDrop: (OutlineNodeIDTransfer, CGPoint, OutlineFlattenedEntry) -> Void

  var body: some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: OutlineRowLayoutSpec.dropSlotHitHeight)
      .contentShape(Rectangle())
      .overlay(alignment: .leading) {
        if let activePlacement {
          Rectangle()
            .fill(Color.accentColor)
            .frame(height: OutlineRowLayoutSpec.dropIndicatorThickness)
            .padding(.leading, outlineDropIndicatorLeadingInset(depth: targetEntry.depth, placement: activePlacement))
            .padding(.trailing, OutlineRowLayoutSpec.dropIndicatorTrailingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
      }
      .onDrop(
        of: [UTType.json],
        delegate: OutlineNodeRowDropDelegate(
          targetEntry: targetEntry,
          placementResolver: placementResolver,
          updatePlacement: updatePlacement,
          performDrop: performDrop
        )
      )
  }
}

struct OutlineVisibleTreeNodeView<RowContent: View>: View {
  let node: OutlineVisibleTreeNode
  let visibleWindow: OutlineVirtualizationWindow
  let dropTargetNodeID: UUID?
  let dropPlacement: OutlineNodeDragDropEngine.Placement?
  let updateDropPlacement: (UUID, OutlineNodeDragDropEngine.Placement?) -> Void
  let performDrop: (OutlineNodeIDTransfer, CGPoint, OutlineFlattenedEntry) -> Void
  let rowContent: (OutlineFlattenedEntry) -> RowContent

  private var estimatedSubtreeHeight: CGFloat {
    CGFloat(node.rowCount) * OutlineVirtualizationMetrics.estimatedRowHeight
  }

  private var estimatedRowHeight: CGFloat {
    OutlineVirtualizationMetrics.estimatedRowHeight
  }

  private var activeTopPlacement: OutlineNodeDragDropEngine.Placement? {
    guard dropTargetNodeID == node.entry.id, dropPlacement == .above else { return nil }
    return .above
  }

  private var activeBottomPlacement: OutlineNodeDragDropEngine.Placement? {
    guard dropTargetNodeID == node.entry.id else { return nil }
    switch dropPlacement {
    case .below, .child:
      return dropPlacement
    case .above, .none:
      return nil
    }
  }

  var body: some View {
    if visibleWindow.intersects(startIndex: node.rowIndex, rowCount: node.rowCount) {
      VStack(alignment: .leading, spacing: 0) {
        if visibleWindow.contains(node.rowIndex) {
          rowContent(node.entry)
        } else {
          Color.clear
            .frame(maxWidth: .infinity, minHeight: estimatedRowHeight)
        }

        if !node.entry.isCollapsed && !node.children.isEmpty {
          OutlineChildrenContainer {
            OutlineVisibleTreeRenderer(
              nodes: node.children,
              visibleWindow: visibleWindow,
              dropTargetNodeID: dropTargetNodeID,
              dropPlacement: dropPlacement,
              updateDropPlacement: updateDropPlacement,
              performDrop: performDrop,
              rowContent: rowContent
            )
          }
        }
      }
      .overlay(alignment: .topLeading) {
        OutlineNodeDropSlot(
          targetEntry: node.entry,
          activePlacement: activeTopPlacement,
          placementResolver: { _, _ in .above },
          updatePlacement: updateDropPlacement,
          performDrop: performDrop
        )
        .offset(y: -(OutlineRowLayoutSpec.dropSlotHitHeight / 2))
      }
      .overlay(alignment: .bottomLeading) {
        OutlineNodeDropSlot(
          targetEntry: node.entry,
          activePlacement: activeBottomPlacement,
          placementResolver: { dropLocation, targetEntry in
            OutlineNodeDragDropEngine.placementFromBottomSlotLocation(
              dropLocation: dropLocation,
              depth: targetEntry.depth
            )
          },
          updatePlacement: updateDropPlacement,
          performDrop: performDrop
        )
        .offset(y: OutlineRowLayoutSpec.dropSlotHitHeight / 2)
      }
    } else {
      Color.clear
        .frame(maxWidth: .infinity, minHeight: estimatedSubtreeHeight)
    }
  }
}

struct OutlineChildrenContainer<Content: View>: View {
  let content: () -> Content

  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  private var guideLineColor: Color {
    Color(nsColor: .quaternaryLabelColor).opacity(0.85)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(guideLineColor)
        .frame(width: OutlineRowLayoutSpec.guideLineWidth)
        .offset(x: OutlineRowLayoutSpec.childGuideLeadingOffset)
        .padding(.bottom, OutlineRowLayoutSpec.guideLineBottomInset)
    }
    .padding(.leading, OutlineRowLayoutSpec.indentWidth)
  }
}

struct OutlineBreadcrumbItem: Identifiable {
  let id: UUID?
  let text: String
  let isProject: Bool

  var stableID: String {
    if isProject {
      return "project-root"
    }
    return id?.uuidString ?? UUID().uuidString
  }

  var identifier: String { stableID }
}

struct OutlineVisibleProjectionInputs: Equatable {
  let document: OutlineDocument
  let hideCompleted: Bool
  let preservedCompletedNodeIDs: Set<UUID>
  let searchQuery: String
  let zoomPath: [UUID]
  let currentProjectID: UUID
}

enum OutlineBlockSelectionDirection {
  case up
  case down
}
