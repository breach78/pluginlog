import AppKit
import Foundation
import SwiftUI

struct OutlineNodeReminderInlineEditor: View {
  let metadata: ReminderMetadataSnapshot
  let isDrawerOpen: Bool
  let onToggleDrawer: () -> Void
  let onApplyDuePreset: (OutlinerReminderQuickDuePreset) -> Void
  let onClearDue: () -> Void
  let onSetDueDate: (Date, Bool) -> Void
  let onSetRecurrence: (OutlinerRecurrenceSample?) -> Void
  let onCycleRecurrence: () -> Void
  let onSetPriority: (Int) -> Void
  let onCyclePriority: () -> Void

  private let chipSpacing: CGFloat = 6

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: chipSpacing) {
        chipButton(
          icon: "calendar",
          text: dueText,
          color: metadata.dueDate == nil ? .secondary : dueColor
        ) {
          onToggleDrawer()
        }

        chipButton(
          icon: "repeat",
          text: metadata.recurrence?.displayText ?? "반복",
          color: metadata.recurrence == nil ? .secondary : .blue
        ) {
          onCycleRecurrence()
        }

        chipButton(
          icon: "exclamationmark.triangle.fill",
          text: priorityText,
          color: priorityColor
        ) {
          onCyclePriority()
        }

        chipButton(
          icon: isDrawerOpen ? "slider.horizontal.3.circle.fill" : "slider.horizontal.3.circle",
          text: "속성",
          color: .secondary
        ) {
          onToggleDrawer()
        }
      }

      if isDrawerOpen {
        VStack(alignment: .leading, spacing: 10) {
          chipGroup(title: "빠른 날짜") {
            ForEach(OutlinerReminderQuickDuePreset.allCases, id: \.title) { preset in
              chipButton(icon: nil, text: preset.title, color: .secondary) {
                onApplyDuePreset(preset)
              }
            }
            chipButton(icon: nil, text: "없음", color: .secondary) {
              onClearDue()
            }
          }

          HStack(spacing: 10) {
            DatePicker(
              "",
              selection: dueDateBinding,
              displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)

            Toggle("시간", isOn: hasTimeBinding)
              .toggleStyle(.checkbox)
              .font(.sandoll(size: 10))

            if metadata.hasExplicitTime {
              DatePicker(
                "",
                selection: timeBinding,
                displayedComponents: [.hourAndMinute]
              )
              .labelsHidden()
              .datePickerStyle(.compact)
            }
          }

          chipGroup(title: "반복") {
            recurrenceChip("없음", recurrence: nil)
            recurrenceChip("매일", recurrence: .daily(interval: 1))
            recurrenceChip("매주", recurrence: .weekly(interval: 1, weekdays: []))
            recurrenceChip("매월", recurrence: .monthly(interval: 1))
            recurrenceChip("매년", recurrence: .yearly(interval: 1))
          }

          chipGroup(title: "우선순위") {
            priorityChip("없음", priority: 0)
            priorityChip("높음", priority: 1)
            priorityChip("중간", priority: 5)
            priorityChip("낮음", priority: 9)
          }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
      }
    }
  }

  private var dueText: String {
    guard let dueDate = metadata.dueDate else { return "날짜" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = metadata.hasExplicitTime ? "M/d a h:mm" : "M/d"
    return formatter.string(from: dueDate)
  }

  private var dueColor: Color {
    guard let dueDate = metadata.dueDate else { return .secondary }
    if dueDate < .now { return .red }
    if Calendar.autoupdatingCurrent.isDateInToday(dueDate) { return .orange }
    return .secondary
  }

  private var priorityText: String {
    switch metadata.priority {
    case 1...4:
      return "높음"
    case 5:
      return "중간"
    case 6...9:
      return "낮음"
    default:
      return "우선순위"
    }
  }

  private var priorityColor: Color {
    switch metadata.priority {
    case 1...4:
      return .red
    case 5:
      return .orange
    case 6...9:
      return .blue
    default:
      return .secondary
    }
  }

  private var dueDateBinding: Binding<Date> {
    Binding(
      get: {
        metadata.dueDate ?? Calendar.autoupdatingCurrent.startOfDay(for: .now)
      },
      set: { newValue in
        onSetDueDate(newValue, metadata.hasExplicitTime)
      }
    )
  }

  private var hasTimeBinding: Binding<Bool> {
    Binding(
      get: { metadata.hasExplicitTime },
      set: { newValue in
        let baseDate = metadata.dueDate ?? Calendar.autoupdatingCurrent.startOfDay(for: .now)
        onSetDueDate(baseDate, newValue)
      }
    )
  }

  private var timeBinding: Binding<Date> {
    Binding(
      get: { metadata.dueDate ?? .now },
      set: { newValue in
        let calendar = Calendar.autoupdatingCurrent
        let currentDate = metadata.dueDate ?? calendar.startOfDay(for: .now)
        let time = calendar.dateComponents([.hour, .minute], from: newValue)
        let mergedDate = calendar.date(
          bySettingHour: time.hour ?? 9,
          minute: time.minute ?? 0,
          second: 0,
          of: currentDate
        ) ?? currentDate
        onSetDueDate(mergedDate, true)
      }
    )
  }

  @ViewBuilder
  private func chipGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.sandoll(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
      HStack(spacing: chipSpacing) {
        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func recurrenceChip(_ title: String, recurrence: OutlinerRecurrenceSample?) -> some View {
    let isSelected = recurrence == metadata.recurrence
    chipButton(icon: nil, text: title, color: isSelected ? .blue : .secondary) {
      onSetRecurrence(recurrence)
    }
  }

  @ViewBuilder
  private func priorityChip(_ title: String, priority: Int) -> some View {
    let isSelected = priority == metadata.priority
    chipButton(icon: nil, text: title, color: isSelected ? priorityColor : .secondary) {
      onSetPriority(priority)
    }
  }

  @ViewBuilder
  private func chipButton(
    icon: String?,
    text: String,
    color: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 4) {
        if let icon {
          Image(systemName: icon)
            .font(.system(size: 9, weight: .medium))
        }
        Text(text)
          .font(.sandoll(size: 10, weight: .medium))
          .lineLimit(1)
      }
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(color.opacity(0.1))
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Node-Based Row Views

private struct OutlineNodeBadgeView: View {
  let badge: OutlineNodeBadgeData

  var body: some View {
    if !badge.isEmpty {
      HStack(spacing: 4) {
        if let dueDate = badge.dueDate {
          badgePill(
            icon: "calendar",
            text: Self.formatDate(dueDate, hasExplicitTime: badge.hasExplicitTime),
            color: Self.dueDateColor(dueDate)
          )
        }
        if let recurrenceText = badge.recurrenceText {
          badgePill(icon: "repeat", text: recurrenceText, color: .blue)
        }
        if badge.priority > 0 {
          badgePill(
            icon: "exclamationmark.triangle.fill",
            text: Self.priorityLabel(badge.priority),
            color: Self.priorityColor(badge.priority)
          )
        }
      }
    }
  }

  @ViewBuilder
  private func badgePill(icon: String, text: String, color: Color) -> some View {
    HStack(spacing: 2) {
      Image(systemName: icon)
        .font(.system(size: 8))
      Text(text)
        .font(.sandoll(size: 9, weight: .medium))
    }
    .foregroundStyle(color)
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(color.opacity(0.1))
    .cornerRadius(3)
  }

  private static func formatDate(_ date: Date, hasExplicitTime: Bool) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
      formatter.dateFormat = hasExplicitTime ? "a h:mm" : "'오늘'"
      return hasExplicitTime ? "오늘 " + formatter.string(from: date) : formatter.string(from: date)
    } else if calendar.isDateInTomorrow(date) {
      formatter.dateFormat = hasExplicitTime ? "a h:mm" : "'내일'"
      return hasExplicitTime ? "내일 " + formatter.string(from: date) : formatter.string(from: date)
    } else {
      formatter.dateFormat = hasExplicitTime ? "M/d a h:mm" : "M/d"
      return formatter.string(from: date)
    }
  }

  private static func dueDateColor(_ date: Date) -> Color {
    if date < Date() { return .red }
    if Calendar.current.isDateInToday(date) { return .orange }
    return .secondary
  }

  private static func priorityLabel(_ priority: Int) -> String {
    switch priority {
    case 1...4: return "높음"
    case 5: return "중간"
    case 6...9: return "낮음"
    default: return ""
    }
  }

  private static func priorityColor(_ priority: Int) -> Color {
    switch priority {
    case 1...4: return .red
    case 5: return .orange
    case 6...9: return .blue
    default: return .secondary
    }
  }
}

enum OutlineNodeRowMetrics {
  static let indentWidth: CGFloat = OutlineRowLayoutSpec.indentWidth
  static let controlSlotWidth: CGFloat = OutlineRowLayoutSpec.controlSlotWidth
  static let bulletAreaWidth: CGFloat = OutlineRowLayoutSpec.markerSlotWidth
  static let rowMinHeight: CGFloat = OutlineRowLayoutSpec.rowMinHeight
  static let rowVerticalPadding: CGFloat = OutlineRowLayoutSpec.rowVerticalPadding
  static let markerReferenceHeight: CGFloat = 20
  static let bulletSize: CGFloat = 6
  static let checkboxSize: CGFloat = 14
  static let collapsedParentBulletExpansion: CGFloat = 8
  static let collapsedParentCheckboxExpansion: CGFloat = 0
  static let subtreeCheckboxOutlineSize: CGFloat = 18
  static let subtreeCheckboxCornerRadius: CGFloat = 0
  static let collapsedParentCheckboxCornerRadius: CGFloat = 2
  static let collapseTriangleSize: CGFloat = 12
  static let subtreeIndicatorSize: CGFloat = 15
  static let bulletVisualVerticalNudge: CGFloat = 2
  static let markerAdditionalLift: CGFloat = -3
  static let collapseAdditionalLift: CGFloat = 0
  static let bulletAdditionalDrop: CGFloat = 1
  static let checkboxAdditionalDrop: CGFloat = 3
  static let cloneDiamondScale: CGFloat = 0.8

  static var textLineHeight: CGFloat {
    OutlineRowLayoutSpec.textLineHeight
  }

  static var firstLineMarkerSlotHeight: CGFloat {
    max(textLineHeight, checkboxSize, collapseTriangleSize)
  }

  static var paragraphStyle: NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    style.lineSpacing = OutlineRowLayoutSpec.textLineSpacing
    style.minimumLineHeight = OutlineRowLayoutSpec.rowMinHeight
    style.maximumLineHeight = OutlineRowLayoutSpec.rowMinHeight
    return style
  }

  static var markerVerticalOffset: CGFloat {
    -((markerReferenceHeight - textLineHeight) / 2)
  }

  static var bulletVerticalOffset: CGFloat {
    markerVerticalOffset + bulletVisualVerticalNudge + markerAdditionalLift + bulletAdditionalDrop
  }

  static var checkboxVerticalOffset: CGFloat {
    markerVerticalOffset + markerAdditionalLift + checkboxAdditionalDrop
  }

  static var collapseVerticalOffset: CGFloat {
    markerVerticalOffset + collapseAdditionalLift
  }

  static var bulletFillColor: Color {
    Color(nsColor: .tertiaryLabelColor).opacity(0.95)
  }

  static var checkboxTintColor: Color {
    bulletFillColor
  }

  static var collapsedParentMarkerTintColor: Color {
    bulletFillColor.opacity(0.64)
  }

  static var subtreeIndicatorColor: Color {
    Color(nsColor: .quaternaryLabelColor).opacity(0.4)
  }

  static var cloneBulletDiamondSize: CGFloat {
    (bulletSize + 2) * cloneDiamondScale
  }

  static var cloneSubtreeDiamondSize: CGFloat {
    subtreeIndicatorSize * cloneDiamondScale
  }
}

struct OutlineCloneTaskCheckbox: View {
  let isCompleted: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .stroke(OutlineNodeRowMetrics.checkboxTintColor, lineWidth: 1.25)
        .rotationEffect(.degrees(45))
      if isCompleted {
        Image(systemName: "checkmark")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(OutlineNodeRowMetrics.checkboxTintColor)
      }
    }
    .frame(
      width: OutlineNodeRowMetrics.checkboxSize,
      height: OutlineNodeRowMetrics.checkboxSize
    )
  }
}

final class OutlineNodeRowEditorTextView: NSTextView {
  var onFocusAcquired: (() -> Void)?
  var onMeasuredContentHeightChange: ((CGFloat) -> Void)?
  var onCommandToggleType: (() -> Void)?
  private var lastReportedContentHeight: CGFloat = 0
  private var lastMeasuredWidth: CGFloat = 0
  private var pendingMeasuredContentHeight: CGFloat?
  private var hasScheduledMeasuredContentHeightDispatch = false
  private var pendingResponderSyncRequest: ResponderSyncRequest?
  private var hasScheduledResponderSync = false

  private struct ResponderSyncRequest {
    let isFocused: Bool
    let requestedSelection: NSRange?
    let onRequestedCursorApplied: (() -> Void)?
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags == .command,
       event.charactersIgnoringModifiers?.lowercased() == "a" {
      selectAll(nil)
      return true
    }
    if flags == .command,
       !hasMarkedText(),
       event.keyCode == 36 || event.keyCode == 76 {
      onCommandToggleType?()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func selectAll(_ sender: Any?) {
    let length = (string as NSString).length
    setSelectedRange(NSRange(location: 0, length: length))
  }

  override var intrinsicContentSize: NSSize {
    guard let layoutManager, let textContainer else {
      return NSSize(width: NSView.noIntrinsicMetric, height: OutlineRowLayoutSpec.rowMinHeight)
    }

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    let contentHeight = ceil(usedRect.height)
    let height = max(
      OutlineRowLayoutSpec.rowMinHeight,
      contentHeight
    )
    return NSSize(width: NSView.noIntrinsicMetric, height: height)
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    let measuredWidth = max(1, newSize.width)
    let widthChanged = abs(lastMeasuredWidth - measuredWidth) > 0.5
    lastMeasuredWidth = measuredWidth
    textContainer?.containerSize = NSSize(
      width: measuredWidth,
      height: CGFloat.greatestFiniteMagnitude
    )
    let heightChanged = reportMeasuredContentHeightIfNeeded()
    if widthChanged || heightChanged {
      invalidateIntrinsicContentSize()
    }
  }

  override func didChangeText() {
    super.didChangeText()
    if reportMeasuredContentHeightIfNeeded() {
      invalidateIntrinsicContentSize()
    }
  }

  override func layout() {
    super.layout()
    if reportMeasuredContentHeightIfNeeded() {
      invalidateIntrinsicContentSize()
    }
  }

  override func becomeFirstResponder() -> Bool {
    let didBecomeFirstResponder = super.becomeFirstResponder()
    if didBecomeFirstResponder {
      onFocusAcquired?()
    }
    return didBecomeFirstResponder
  }

  @discardableResult
  func reportMeasuredContentHeightIfNeeded() -> Bool {
    guard let layoutManager, let textContainer else { return false }
    layoutManager.ensureLayout(for: textContainer)
    let contentHeight = ceil(layoutManager.usedRect(for: textContainer).height)
    guard abs(contentHeight - lastReportedContentHeight) > 0.5 else { return false }
    lastReportedContentHeight = contentHeight
    enqueueMeasuredContentHeightChange(contentHeight)
    return true
  }

  private func enqueueMeasuredContentHeightChange(_ contentHeight: CGFloat) {
    pendingMeasuredContentHeight = contentHeight
    guard !hasScheduledMeasuredContentHeightDispatch else { return }
    hasScheduledMeasuredContentHeightDispatch = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.hasScheduledMeasuredContentHeightDispatch = false
      guard let pendingMeasuredContentHeight = self.pendingMeasuredContentHeight else { return }
      self.pendingMeasuredContentHeight = nil
      self.onMeasuredContentHeightChange?(pendingMeasuredContentHeight)
    }
  }

  func scheduleResponderSync(
    isFocused: Bool,
    requestedSelection: NSRange?,
    onRequestedCursorApplied: (() -> Void)?
  ) {
    pendingResponderSyncRequest = ResponderSyncRequest(
      isFocused: isFocused,
      requestedSelection: requestedSelection,
      onRequestedCursorApplied: onRequestedCursorApplied
    )
    guard !hasScheduledResponderSync else { return }
    hasScheduledResponderSync = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.hasScheduledResponderSync = false
      guard let request = self.pendingResponderSyncRequest else { return }
      self.pendingResponderSyncRequest = nil
      self.applyResponderSync(request)
    }
  }

  func applySelectedRangeIfNeeded(_ range: NSRange) {
    guard !NSEqualRanges(selectedRange(), range) else { return }
    setSelectedRange(range)
  }

  private func applyResponderSync(_ request: ResponderSyncRequest) {
    if request.isFocused {
      if window?.firstResponder !== self {
        window?.makeFirstResponder(self)
      }
      if let requestedSelection = request.requestedSelection {
        applySelectedRangeIfNeeded(requestedSelection)
        request.onRequestedCursorApplied?()
      }
      return
    }

    if window?.firstResponder === self {
      window?.makeFirstResponder(nil)
    }
  }
}

struct OutlineNodeRowTextField: NSViewRepresentable {
  @Binding var text: String
  var isFocused: Bool
  var requestedCursorPosition: Int?
  var onRequestedCursorApplied: (() -> Void)?
  var onMeasuredContentHeightChange: (CGFloat) -> Void
  var onFocusAcquired: () -> Void
  var onEditingEnded: () -> Void
  var onInsertNewline: (Int) -> Void
  var onDeleteBackwardAtStart: () -> Void
  var onInsertTab: (Int) -> Void
  var onInsertBacktab: (Int) -> Void
  var onMoveLeftFromStart: () -> Void
  var onMoveRightFromEnd: () -> Void
  var onMoveUp: () -> Void
  var onMoveDown: () -> Void
  var onShiftMoveUp: () -> Void
  var onShiftMoveDown: () -> Void
  var onCommitAndToggleType: () -> Void

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: OutlineNodeRowTextField
    var isUpdating = false

    init(parent: OutlineNodeRowTextField) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard !isUpdating, let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
    }

    func textDidEndEditing(_ notification: Notification) {
      guard !isUpdating else { return }
      parent.onEditingEnded()
    }

    func textView(
      _ textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      let canNavigateBetweenRows = canNavigateAcrossRows(in: textView)
      let selectedRange = textView.selectedRange()
      let textLength = (textView.string as NSString).length

      if commandSelector == #selector(NSResponder.selectAll(_:)) {
        textView.setSelectedRange(NSRange(location: 0, length: textLength))
        return true
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.insertLineBreak(_:))
        || commandSelector == #selector(NSStandardKeyBindingResponding.insertNewlineIgnoringFieldEditor(_:))
      {
        insertSoftLineBreak(in: textView)
        return true
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.insertNewline(_:)) {
        if shouldInsertSoftLineBreak {
          insertSoftLineBreak(in: textView)
          return true
        }
        parent.onInsertNewline(textView.selectedRange().location)
        return true
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.deleteBackward(_:)) {
        if selectedRange.location == 0 && selectedRange.length == 0 {
          parent.onDeleteBackwardAtStart()
          return true
        }
        return false
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.insertTab(_:)) {
        parent.onInsertTab(selectedRange.location)
        return true
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.insertBacktab(_:)) {
        parent.onInsertBacktab(selectedRange.location)
        return true
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.moveLeft(_:)) {
        if selectedRange.length == 0, selectedRange.location == 0 {
          parent.onMoveLeftFromStart()
          return true
        }
        return false
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.moveRight(_:)) {
        if selectedRange.length == 0, selectedRange.location == textLength {
          parent.onMoveRightFromEnd()
          return true
        }
        return false
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.moveUp(_:)) {
        guard canNavigateBetweenRows, isCaretOnFirstVisualLine(in: textView) else {
          return false
        }
        parent.onMoveUp()
        return true
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.moveDown(_:)) {
        guard canNavigateBetweenRows, isCaretOnLastVisualLine(in: textView) else {
          return false
        }
        parent.onMoveDown()
        return true
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.moveUpAndModifySelection(_:)) {
        guard shouldPromoteShiftSelectionToBlock(
          in: textView,
          selectedRange: selectedRange,
          textLength: textLength,
          direction: .up
        ) else {
          return false
        }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        parent.onShiftMoveUp()
        return true
      }

      if commandSelector == #selector(NSStandardKeyBindingResponding.moveDownAndModifySelection(_:)) {
        guard shouldPromoteShiftSelectionToBlock(
          in: textView,
          selectedRange: selectedRange,
          textLength: textLength,
          direction: .down
        ) else {
          return false
        }
        textView.setSelectedRange(NSRange(location: textLength, length: 0))
        parent.onShiftMoveDown()
        return true
      }

      return false
    }

    private func canNavigateAcrossRows(in textView: NSTextView) -> Bool {
      !textView.hasMarkedText() && textView.selectedRange().length == 0
    }

    private enum SelectionBoundaryDirection {
      case up
      case down
    }

    private func shouldPromoteShiftSelectionToBlock(
      in textView: NSTextView,
      selectedRange: NSRange,
      textLength: Int,
      direction: SelectionBoundaryDirection
    ) -> Bool {
      guard !textView.hasMarkedText() else { return false }
      switch direction {
      case .up:
        guard let lineRange = visualLineGlyphRange(in: textView, selectedLocation: selectedRange.location) else {
          return true
        }
        return lineRange.location == 0
      case .down:
        guard let layoutManager = textView.layoutManager else { return true }
        guard let lineRange = visualLineGlyphRange(
          in: textView,
          selectedLocation: min(NSMaxRange(selectedRange), textLength)
        ) else {
          return true
        }
        return NSMaxRange(lineRange) >= layoutManager.numberOfGlyphs
      }
    }

    private var shouldInsertSoftLineBreak: Bool {
      NSApp.currentEvent?.modifierFlags.contains(.shift) == true
    }

    private func insertSoftLineBreak(in textView: NSTextView) {
      textView.insertText("\n", replacementRange: textView.selectedRange())
    }

    private func isCaretOnFirstVisualLine(in textView: NSTextView) -> Bool {
      guard let lineRange = currentVisualLineGlyphRange(in: textView) else { return true }
      return lineRange.location == 0
    }

    private func isCaretOnLastVisualLine(in textView: NSTextView) -> Bool {
      guard let layoutManager = textView.layoutManager else { return true }
      guard let lineRange = currentVisualLineGlyphRange(in: textView) else { return true }
      return NSMaxRange(lineRange) >= layoutManager.numberOfGlyphs
    }

    private func currentVisualLineGlyphRange(in textView: NSTextView) -> NSRange? {
      visualLineGlyphRange(in: textView, selectedLocation: textView.selectedRange().location)
    }

    private func visualLineGlyphRange(
      in textView: NSTextView,
      selectedLocation: Int
    ) -> NSRange? {
      guard let layoutManager = textView.layoutManager,
        let textContainer = textView.textContainer
      else {
        return nil
      }

      layoutManager.ensureLayout(for: textContainer)
      let glyphCount = layoutManager.numberOfGlyphs
      guard glyphCount > 0 else { return NSRange(location: 0, length: 0) }

      let stringLength = (textView.string as NSString).length
      let characterIndex: Int
      if selectedLocation >= stringLength {
        characterIndex = max(0, stringLength - 1)
      } else {
        characterIndex = selectedLocation
      }

      let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
      var lineRange = NSRange(location: 0, length: 0)
      layoutManager.lineFragmentRect(
        forGlyphAt: min(glyphIndex, max(0, glyphCount - 1)),
        effectiveRange: &lineRange,
        withoutAdditionalLayout: true
      )
      return lineRange
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> OutlineNodeRowEditorTextView {
    let textView = OutlineNodeRowEditorTextView()
    textView.isRichText = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.autoresizingMask = [.width]
    textView.textContainerInset = .zero
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.lineBreakMode = .byWordWrapping
    textView.textContainer?.containerSize = NSSize(
      width: 1,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.delegate = context.coordinator
    textView.font = OutlinerFonts.nsFont(size: OutlinerCanvasMetrics.fontSize)
    textView.textColor = .labelColor
    textView.insertionPointColor = .labelColor
    textView.string = text
    textView.onFocusAcquired = {
      context.coordinator.parent.onFocusAcquired()
    }
    textView.onMeasuredContentHeightChange = { height in
      context.coordinator.parent.onMeasuredContentHeightChange(height)
    }
    textView.onCommandToggleType = {
      context.coordinator.parent.onCommitAndToggleType()
    }

    applyEditorTypingAttributes(to: textView)
    applyFormatting(to: textView)
    return textView
  }

  func updateNSView(_ textView: OutlineNodeRowEditorTextView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.isUpdating = true
    textView.onMeasuredContentHeightChange = { height in
      context.coordinator.parent.onMeasuredContentHeightChange(height)
    }
    textView.onCommandToggleType = {
      context.coordinator.parent.onCommitAndToggleType()
    }
    let targetFont = OutlinerFonts.nsFont(size: OutlinerCanvasMetrics.fontSize)
    if textView.font != targetFont {
      textView.font = targetFont
      applyFormatting(to: textView)
    } else {
      applyEditorTypingAttributes(to: textView)
    }
    if textView.string != text {
      let selectedRange = clampedSelectedRange(textView.selectedRange(), in: textView.string)
      textView.string = text
      applyFormatting(
        to: textView,
        preservingSelectedRange: clampedSelectedRange(selectedRange, in: text)
      )
    }
    context.coordinator.isUpdating = false

    let requestedSelection = requestedCursorPosition.map {
      clampedSelectedRange(NSRange(location: $0, length: 0), in: textView.string)
    }
    if isFocused || textView.window?.firstResponder === textView || requestedSelection != nil {
      textView.scheduleResponderSync(
        isFocused: isFocused,
        requestedSelection: requestedSelection,
        onRequestedCursorApplied: onRequestedCursorApplied
      )
    }
  }

  private var editorAttributes: [NSAttributedString.Key: Any] {
    [
      .font: OutlinerFonts.nsFont(size: OutlinerCanvasMetrics.fontSize),
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: OutlineNodeRowMetrics.paragraphStyle,
    ]
  }

  private func applyEditorTypingAttributes(to textView: OutlineNodeRowEditorTextView) {
    var typingAttributes = textView.typingAttributes
    editorAttributes.forEach { key, value in
      typingAttributes[key] = value
    }
    textView.typingAttributes = typingAttributes
  }

  private func applyFormatting(
    to textView: OutlineNodeRowEditorTextView,
    preservingSelectedRange preservedSelectedRange: NSRange? = nil
  ) {
    let font = OutlinerFonts.nsFont(size: OutlinerCanvasMetrics.fontSize)
    let attrStr = OutlineInlineFormatter.attributedString(
      from: textView.string,
      fontSize: OutlinerFonts.resolvedSize(OutlinerCanvasMetrics.fontSize),
      baseFont: font,
      paragraphStyle: OutlineNodeRowMetrics.paragraphStyle
    )
    let selectedRange = preservedSelectedRange
      ?? clampedSelectedRange(textView.selectedRange(), in: textView.string)
    textView.textStorage?.setAttributedString(attrStr)
    applyEditorTypingAttributes(to: textView)
    textView.applySelectedRangeIfNeeded(clampedSelectedRange(selectedRange, in: textView.string))
    _ = textView.reportMeasuredContentHeightIfNeeded()
    textView.invalidateIntrinsicContentSize()
  }

  private func clampedSelectedRange(_ range: NSRange, in text: String) -> NSRange {
    let length = (text as NSString).length
    let location = max(0, min(range.location, length))
    let selectedLength = max(0, min(range.length, length - location))
    return NSRange(location: location, length: selectedLength)
  }
}

private final class OutlineProjectTitleTextFieldCell: NSTextFieldCell {
  private func measuredTextHeight() -> CGFloat {
    if let font {
      return ceil(font.ascender - font.descender + font.leading)
    }
    return ceil(cellSize.height)
  }

  private func verticallyAlignedRect(for bounds: NSRect) -> NSRect {
    let targetHeight = min(bounds.height, measuredTextHeight())
    let alignedY = bounds.origin.y + floor((bounds.height - targetHeight) / 2)
    return NSRect(x: bounds.origin.x, y: alignedY, width: bounds.width, height: targetHeight)
  }

  override func titleRect(forBounds rect: NSRect) -> NSRect {
    verticallyAlignedRect(for: rect)
  }

  override func drawingRect(forBounds rect: NSRect) -> NSRect {
    titleRect(forBounds: rect)
  }

  private func editingRect(forBounds rect: NSRect) -> NSRect {
    titleRect(forBounds: rect)
  }

  override func edit(
    withFrame rect: NSRect,
    in controlView: NSView,
    editor textObj: NSText,
    delegate: Any?,
    event: NSEvent?
  ) {
    super.edit(
      withFrame: editingRect(forBounds: rect),
      in: controlView,
      editor: textObj,
      delegate: delegate,
      event: event
    )
  }

  override func select(
    withFrame rect: NSRect,
    in controlView: NSView,
    editor textObj: NSText,
    delegate: Any?,
    start selStart: Int,
    length selLength: Int
  ) {
    super.select(
      withFrame: editingRect(forBounds: rect),
      in: controlView,
      editor: textObj,
      delegate: delegate,
      start: selStart,
      length: selLength
    )
  }
}

final class OutlineProjectTitleTextField: NSTextField {
  var onUserFocusAttempt: (() -> Void)?
  var onFocusEnded: (() -> Void)?
  private var allowsNextFocusAcquisition = false

  func allowProgrammaticFocus() {
    allowsNextFocusAcquisition = true
  }

  override func mouseDown(with event: NSEvent) {
    allowsNextFocusAcquisition = true
    onUserFocusAttempt?()
    super.mouseDown(with: event)
  }

  override func becomeFirstResponder() -> Bool {
    let isAlreadyFirstResponder =
      window?.firstResponder === self || window?.firstResponder === currentEditor()
    guard allowsNextFocusAcquisition || isAlreadyFirstResponder else {
      return false
    }

    let didBecomeFirstResponder = super.becomeFirstResponder()
    if didBecomeFirstResponder {
      onUserFocusAttempt?()
    }
    allowsNextFocusAcquisition = false
    return didBecomeFirstResponder
  }

  override func resignFirstResponder() -> Bool {
    allowsNextFocusAcquisition = false
    let didResign = super.resignFirstResponder()
    if didResign {
      onFocusEnded?()
    }
    return didResign
  }
}

struct OutlineProjectTitleInputField: NSViewRepresentable {
  @Binding var text: String
  @Binding var isFocused: Bool
  let placeholder: String
  let font: NSFont
  let textColor: NSColor
  let onFocusAttempt: () -> Void
  let onCommit: () -> Void

  @MainActor
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: OutlineProjectTitleInputField
    var hasPendingUserFocusAttempt = false

    init(parent: OutlineProjectTitleInputField) {
      self.parent = parent
    }

    func registerUserFocusAttempt() {
      hasPendingUserFocusAttempt = true
      if !parent.isFocused {
        parent.isFocused = true
      }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
      hasPendingUserFocusAttempt = false
      if !parent.isFocused {
        parent.isFocused = true
      }
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      let updatedText = currentEditor(for: field)?.string ?? field.stringValue
      if parent.text != updatedText {
        parent.text = updatedText
      }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
      guard let field = notification.object as? OutlineProjectTitleTextField else { return }
      let endingEventType = NSApp.currentEvent?.type
      DispatchQueue.main.async {
        guard let window = field.window else {
          self.parent.onCommit()
          return
        }
        if self.isFirstResponder(for: field, in: window) {
          return
        }
        if self.parent.isFocused,
           self.shouldPreserveFocus(for: endingEventType)
        {
          field.allowProgrammaticFocus()
          window.makeFirstResponder(field)
          if self.isFirstResponder(for: field, in: window) {
            return
          }
        }
        if self.parent.isFocused {
          self.parent.isFocused = false
        }
        self.parent.onCommit()
      }
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        control.window?.makeFirstResponder(nil)
        return true
      }
      return false
    }

    func isFirstResponder(for field: NSTextField, in window: NSWindow) -> Bool {
      window.firstResponder === field || window.firstResponder === field.currentEditor()
    }

    func shouldPreserveFocus(for eventType: NSEvent.EventType?) -> Bool {
      switch eventType {
      case .mouseMoved, .mouseExited, .cursorUpdate, .scrollWheel:
        true
      default:
        false
      }
    }

    func currentEditor(for field: NSTextField) -> NSTextView? {
      field.currentEditor() as? NSTextView
    }

    func hasMarkedText(in field: NSTextField) -> Bool {
      currentEditor(for: field)?.hasMarkedText() == true
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> OutlineProjectTitleTextField {
    let field = OutlineProjectTitleTextField()
    field.delegate = context.coordinator
    field.cell = OutlineProjectTitleTextFieldCell(textCell: text)
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.isEditable = true
    field.isSelectable = true
    field.usesSingleLineMode = true
    field.maximumNumberOfLines = 1
    field.lineBreakMode = .byClipping
    field.font = font
    field.textColor = textColor
    field.stringValue = text
    field.placeholderString = placeholder
    if let cell = field.cell as? NSTextFieldCell {
      cell.wraps = false
      cell.isScrollable = true
      cell.lineBreakMode = .byClipping
      cell.usesSingleLineMode = true
    }
    field.onUserFocusAttempt = { [weak coordinator = context.coordinator] in
      coordinator?.registerUserFocusAttempt()
      coordinator?.parent.onFocusAttempt()
    }
    field.onFocusEnded = { [weak coordinator = context.coordinator] in
      coordinator?.hasPendingUserFocusAttempt = false
    }
    return field
  }

  func updateNSView(_ field: OutlineProjectTitleTextField, context: Context) {
    context.coordinator.parent = self

    let currentEditor = context.coordinator.currentEditor(for: field)
    let isEditing = currentEditor != nil
    let isComposing = context.coordinator.hasMarkedText(in: field)

    if !isEditing && field.stringValue != text {
      field.stringValue = text
    }

    if field.placeholderString != placeholder {
      field.placeholderString = placeholder
    }

    if field.font?.fontName != font.fontName || abs((field.font?.pointSize ?? 0) - font.pointSize) > 0.5 {
      field.font = font
    }

    if field.textColor != textColor {
      field.textColor = textColor
    }

    guard let window = field.window else { return }
    let isFirstResponder = context.coordinator.isFirstResponder(for: field, in: window)

    if isFocused && !isFirstResponder {
      field.allowProgrammaticFocus()
      window.makeFirstResponder(field)
    } else if !isFocused && isFirstResponder && !isComposing {
      guard !context.coordinator.hasPendingUserFocusAttempt else { return }
      window.makeFirstResponder(nil)
    }
  }
}
