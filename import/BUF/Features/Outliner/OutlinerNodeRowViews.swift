import AppKit
import Foundation
import SwiftUI

struct OutlineNodeRow: View {
  let entry: OutlineFlattenedEntry
  let renderProfile: OutlineRenderProfile
  let displayDepth: Int
  let isMirrorPlacement: Bool
  let isFocused: Bool
  let isHovered: Bool
  let isSelected: Bool
  let dragTransfer: OutlineNodeIDTransfer
  let showsAccessoryBand: Bool
  let reminderMetadata: ReminderMetadataSnapshot
  let reminderReadOnlySurface: ReminderSyncReadOnlySurface?
  let reminderConflictSurface: OutlineNodeReminderConflictSurface?
  let draftSession: DraftSessionBridge
  let actionHandler: any OutlinerRowActionHandler
  let isCloned: Bool
  let requestedCursorPosition: Int?

  @State private var localText: String
  @State private var hasPendingLocalTextCommit = false
  @State private var isReminderDrawerOpen = false
  @State private var suppressRowTapFocus = false
  @State private var measuredTextContentHeight: CGFloat = OutlineRowLayoutSpec.rowMinHeight

  init(
    entry: OutlineFlattenedEntry,
    renderProfile: OutlineRenderProfile,
    displayDepth: Int? = nil,
    isMirrorPlacement: Bool,
    isFocused: Bool,
    isHovered: Bool,
    isSelected: Bool,
    dragTransfer: OutlineNodeIDTransfer,
    showsAccessoryBand: Bool,
    reminderMetadata: ReminderMetadataSnapshot,
    reminderReadOnlySurface: ReminderSyncReadOnlySurface?,
    reminderConflictSurface: OutlineNodeReminderConflictSurface?,
    draftSession: DraftSessionBridge,
    actionHandler: any OutlinerRowActionHandler,
    isCloned: Bool,
    requestedCursorPosition: Int? = nil
  ) {
    self.entry = entry
    self.renderProfile = renderProfile
    self.displayDepth = displayDepth ?? entry.depth
    self.isMirrorPlacement = isMirrorPlacement
    self.isFocused = isFocused
    self.isHovered = isHovered
    self.isSelected = isSelected
    self.dragTransfer = dragTransfer
    self.showsAccessoryBand = showsAccessoryBand
    self.reminderMetadata = reminderMetadata
    self.reminderReadOnlySurface = reminderReadOnlySurface
    self.reminderConflictSurface = reminderConflictSurface
    self.draftSession = draftSession
    self.actionHandler = actionHandler
    self.isCloned = isCloned
    self.requestedCursorPosition = requestedCursorPosition
    _localText = State(initialValue: entry.node.text)
  }

  private var referenceSuggestions: [OutlineBlockReferenceSuggestion] {
    guard renderProfile.showsReferenceSuggestions else { return [] }
    return entry.node.type.isReference ? [] : actionHandler.referenceSuggestions(for: localText)
  }

  private func commitLocalTextIfNeeded() {
    let normalizedText = normalizedLocalText()
    guard hasPendingLocalTextCommit || normalizedText != entry.node.text else { return }
    hasPendingLocalTextCommit = false
    guard normalizedText != entry.node.text else { return }
    if OutlinerEditingGranularityFlags.useNodeDraftBuffer {
      draftSession.commitPatch(
        NodePatch(
          nodeID: entry.id,
          canonicalID: entry.node.canonicalID,
          oldText: entry.node.text,
          newText: normalizedText,
          isCloned: isCloned
        )
      )
    } else {
      actionHandler.onTextEdit(nodeID: entry.id, newText: normalizedText)
    }
  }

  private func flushPendingTextCommit() {
    commitLocalTextIfNeeded()
  }

  private func normalizedLocalText() -> String {
    let normalizedText = actionHandler.normalizeTextBeforeCommit(nodeID: entry.id, text: localText)
    if localText != normalizedText {
      localText = normalizedText
    }
    return normalizedText
  }

  private func textAfterInsertNewline(
    committedText: String,
    cursorPosition: Int
  ) -> String {
    let nsText = committedText as NSString
    let textLength = nsText.length
    let clampedCursor = max(0, min(cursorPosition, textLength))
    guard clampedCursor < textLength else { return committedText }
    return nsText.substring(to: clampedCursor)
  }

  private func commitPendingTextAndInsertNewline(cursorPosition: Int) {
    let committedText = normalizedLocalText()
    localText = textAfterInsertNewline(
      committedText: committedText,
      cursorPosition: cursorPosition
    )
    actionHandler.onInsertNewline(
      nodeID: entry.id,
      committedText: committedText,
      cursorPosition: cursorPosition
    )
    hasPendingLocalTextCommit = false
  }

  private func commitPendingTextAndToggleType() {
    actionHandler.onCommitAndToggleType(nodeID: entry.id, committedText: normalizedLocalText())
    hasPendingLocalTextCommit = false
  }

  private var localTextBinding: Binding<String> {
    Binding(
      get: { localText },
      set: { newValue in
        guard localText != newValue else { return }
        localText = newValue
        hasPendingLocalTextCommit = true
      }
    )
  }

  private func updateMeasuredTextContentHeightIfNeeded(_ height: CGFloat) {
    guard abs(measuredTextContentHeight - height) > 0.5 else { return }
    measuredTextContentHeight = height
  }

  private var attachmentInsetWidth: CGFloat {
    OutlineRowLayoutSpec.leadingAccessoryX(depth: displayDepth)
  }

  private var additionalBottomPadding: CGFloat {
    measuredTextContentHeight > (OutlineRowLayoutSpec.rowMinHeight + 1)
      ? OutlineRowLayoutSpec.multilineBottomPadding
      : 0
  }

  var shouldShowAccessoryBand: Bool {
    guard showsAccessoryBand else { return false }
    return OutlineRowLayoutSpec.showsAccessoryBand(
      isFocused: isFocused,
      isTask: entry.node.type.isTask,
      hasReminderConflict: reminderConflictSurface != nil,
      hasSuggestions: !referenceSuggestionsForAccessory.isEmpty,
      hasAttachments: !entry.node.attachments.isEmpty
    )
  }

  private var referenceSuggestionsForAccessory: [OutlineBlockReferenceSuggestion] {
    guard isFocused, !entry.node.type.isReference else { return [] }
    return referenceSuggestions
  }

  private var showsCollapsedParentMarkerAccent: Bool {
    entry.hasChildren && entry.isCollapsed
  }

  private var isMirrorNode: Bool {
    isMirrorPlacement
  }

  private var collapseControlHeight: CGFloat {
    max(
      OutlineRowLayoutSpec.controlHitAreaHeight,
      measuredTextContentHeight + additionalBottomPadding
    )
  }

  private var showsCollapseIndicator: Bool {
    entry.hasChildren && (isHovered || isFocused || isSelected || entry.isCollapsed)
  }

  private var currentModifierFlags: NSEvent.ModifierFlags {
    NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
  }

  @ViewBuilder
  private var collapseControl: some View {
    ZStack(alignment: .top) {
      Rectangle()
        .fill(entry.hasChildren ? Color.primary.opacity(0.001) : Color.clear)
        .frame(
          width: OutlineRowLayoutSpec.controlSlotWidth,
          height: collapseControlHeight
        )

      if showsCollapseIndicator {
        Image(systemName: entry.isCollapsed ? "chevron.right" : "chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(
            width: OutlineNodeRowMetrics.collapseTriangleSize,
            height: OutlineNodeRowMetrics.firstLineMarkerSlotHeight,
            alignment: .center
          )
          .offset(y: OutlineNodeRowMetrics.collapseVerticalOffset)
      }
    }
    .frame(
      width: OutlineRowLayoutSpec.controlSlotWidth,
      height: collapseControlHeight,
      alignment: .top
    )
    .overlay {
      if entry.hasChildren {
        OutlineMouseHoverTracker { hovering in
          actionHandler.onHoverChange(nodeID: entry.id, isHovering: hovering)
        }
      }
    }
    .contentShape(Rectangle())
    .allowsHitTesting(entry.hasChildren)
    .highPriorityGesture(
      TapGesture().onEnded {
        suppressRowTapFocus = true
        actionHandler.onToggleCollapse(nodeID: entry.id)
        DispatchQueue.main.async {
          suppressRowTapFocus = false
        }
      },
      including: .all
    )
    .accessibilityAddTraits(.isButton)
  }

  @ViewBuilder
  var accessoryBand: some View {
    OutlineNodeRowAccessoryBand(
      leadingAccessoryX: attachmentInsetWidth,
      isFocused: isFocused,
      isTask: entry.node.type.isTask,
      reminderMetadata: reminderMetadata,
      reminderReadOnlySurface: reminderReadOnlySurface,
      reminderConflictSurface: reminderConflictSurface,
      isReminderDrawerOpen: isReminderDrawerOpen,
      referenceSuggestions: referenceSuggestionsForAccessory,
      attachments: entry.node.attachments,
      onToggleReminderDrawer: {
        isReminderDrawerOpen.toggle()
      },
      onReminderAction: { action in
        actionHandler.onReminderAction(nodeID: entry.id, action: action)
      },
      onResolveReminderConflict: { action in
        actionHandler.onResolveReminderConflict(nodeID: entry.id, action: action)
      },
      onInsertReferenceSuggestion: { suggestion in
        actionHandler.onInsertReferenceSuggestion(nodeID: entry.id, suggestion: suggestion)
      }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        Spacer()
          .frame(width: CGFloat(displayDepth) * OutlineNodeRowMetrics.indentWidth)

        collapseControl

        bulletOrCheckbox
        Color.clear
          .frame(width: OutlineRowLayoutSpec.markerTextSpacing)

        if OutlineRowLayoutSpec.usesEditor(isFocused: isFocused, isReference: entry.node.type.isReference) {
          OutlineNodeRowTextField(
            text: localTextBinding,
            isFocused: isFocused,
            requestedCursorPosition: requestedCursorPosition,
            onRequestedCursorApplied: {
              actionHandler.onRequestedCursorApplied(nodeID: entry.id)
            },
            onMeasuredContentHeightChange: { height in
              updateMeasuredTextContentHeightIfNeeded(height)
            },
            onFocusAcquired: {
              actionHandler.onTextEditingBegan(nodeID: entry.id)
              actionHandler.onFocus(nodeID: entry.id, cursorPosition: nil)
            },
            onEditingEnded: {
              flushPendingTextCommit()
              actionHandler.onTextEditingEnded(nodeID: entry.id)
            },
            onInsertNewline: { cursorPosition in
              commitPendingTextAndInsertNewline(cursorPosition: cursorPosition)
            },
            onDeleteBackwardAtStart: {
              flushPendingTextCommit()
              actionHandler.onDeleteBackwardAtStart(nodeID: entry.id)
            },
            onInsertTab: { cursorPosition in
              flushPendingTextCommit()
              actionHandler.onIndent(nodeID: entry.id, cursorPosition: cursorPosition)
            },
            onInsertBacktab: { cursorPosition in
              flushPendingTextCommit()
              actionHandler.onOutdent(nodeID: entry.id, cursorPosition: cursorPosition)
            },
            onMoveLeftFromStart: {
              flushPendingTextCommit()
              actionHandler.onMoveLeftFromStart(nodeID: entry.id)
            },
            onMoveRightFromEnd: {
              flushPendingTextCommit()
              actionHandler.onMoveRightFromEnd(nodeID: entry.id)
            },
            onMoveUp: {
              flushPendingTextCommit()
              actionHandler.onMoveUp(nodeID: entry.id)
            },
            onMoveDown: {
              flushPendingTextCommit()
              actionHandler.onMoveDown(nodeID: entry.id)
            },
            onShiftMoveUp: {
              flushPendingTextCommit()
              actionHandler.onShiftMoveUp(nodeID: entry.id)
            },
            onShiftMoveDown: {
              flushPendingTextCommit()
              actionHandler.onShiftMoveDown(nodeID: entry.id)
            },
            onCommitAndToggleType: {
              commitPendingTextAndToggleType()
            }
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          OutlineNodeRowDisplay(
            text: localText,
            fontSize: OutlinerCanvasMetrics.fontSize,
            onActivate: { cursorPosition, modifiers in
              if modifiers.contains(.command) {
                suppressRowTapFocus = true
                actionHandler.onCommandToggleSelection(nodeID: entry.id)
                DispatchQueue.main.async {
                  suppressRowTapFocus = false
                }
                return
              }
              suppressRowTapFocus = true
              actionHandler.onFocus(nodeID: entry.id, cursorPosition: cursorPosition)
              DispatchQueue.main.async {
                suppressRowTapFocus = false
              }
            },
            onMeasuredContentHeightChange: { height in
              updateMeasuredTextContentHeightIfNeeded(height)
            }
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        Spacer()
      }
      .frame(minHeight: OutlineRowLayoutSpec.rowMinHeight)

    }
    .padding(.vertical, OutlineNodeRowMetrics.rowVerticalPadding)
    .padding(.bottom, additionalBottomPadding)
    .frame(maxWidth: .infinity, minHeight: OutlineRowLayoutSpec.estimatedRowHeight, alignment: .leading)
    .background(
      isSelected ? Color.accentColor.opacity(0.1) : Color.clear
    )
    .contentShape(Rectangle())
    .onTapGesture {
      guard !suppressRowTapFocus else { return }
      OutlineSelectionDiagnostics.log(
        "row.onTap id=\(entry.id.uuidString) command=\(currentModifierFlags.contains(.command)) selected=\(isSelected) focused=\(isFocused)"
      )
      if currentModifierFlags.contains(.command) {
        actionHandler.onCommandToggleSelection(nodeID: entry.id)
        return
      }
      actionHandler.onFocus(nodeID: entry.id, cursorPosition: nil)
    }
    .onChange(of: entry.node.text) { _, newValue in
      if !isFocused {
        if localText != newValue {
          localText = newValue
        }
        hasPendingLocalTextCommit = false
      }
    }
    .onChange(of: isFocused) { _, focused in
      if !focused {
        flushPendingTextCommit()
        if isReminderDrawerOpen {
          isReminderDrawerOpen = false
        }
      }
    }
    .onDisappear {
      flushPendingTextCommit()
    }
  }

  @ViewBuilder
  private var bulletOrCheckbox: some View {
    switch entry.node.type {
    case .bullet:
      draggableMarker {
        markerButton(action: { actionHandler.onZoomIn(nodeID: entry.id) }) {
          ZStack {
            if showsCollapsedParentMarkerAccent {
              if isMirrorNode {
                Rectangle()
                  .fill(OutlineNodeRowMetrics.collapsedParentMarkerTintColor)
                  .frame(
                    width: OutlineNodeRowMetrics.cloneBulletDiamondSize + OutlineNodeRowMetrics.collapsedParentBulletExpansion,
                    height: OutlineNodeRowMetrics.cloneBulletDiamondSize + OutlineNodeRowMetrics.collapsedParentBulletExpansion
                  )
                  .rotationEffect(.degrees(45))
              } else {
                Circle()
                  .fill(OutlineNodeRowMetrics.collapsedParentMarkerTintColor)
                  .frame(
                    width: OutlineNodeRowMetrics.bulletSize + OutlineNodeRowMetrics.collapsedParentBulletExpansion,
                    height: OutlineNodeRowMetrics.bulletSize + OutlineNodeRowMetrics.collapsedParentBulletExpansion
                  )
              }
            }

            if isMirrorNode {
              Rectangle()
                .fill(OutlineNodeRowMetrics.bulletFillColor)
                .frame(
                  width: OutlineNodeRowMetrics.cloneBulletDiamondSize,
                  height: OutlineNodeRowMetrics.cloneBulletDiamondSize
                )
                .rotationEffect(.degrees(45))
            } else {
              Circle()
                .fill(OutlineNodeRowMetrics.bulletFillColor)
                .frame(width: OutlineNodeRowMetrics.bulletSize, height: OutlineNodeRowMetrics.bulletSize)
            }
          }
        }
      }
      .offset(y: OutlineNodeRowMetrics.bulletVerticalOffset)
      .contextMenu {
        Button("줌인") { actionHandler.onZoomIn(nodeID: entry.id) }
        Button("미러") { actionHandler.onCopyBlockReference(nodeID: entry.id) }
        Button("선택 미러") { actionHandler.onCopySelectedBlockReferences() }
        Button("체크박스로 변환") { actionHandler.onToggleType(nodeID: entry.id) }
        Button("파일 첨부") { actionHandler.onAddAttachment(nodeID: entry.id) }
        Divider()
        Button("삭제", role: .destructive) { actionHandler.onDeleteSubtree(nodeID: entry.id) }
      }
    case .task(let completed):
      draggableMarker {
        markerButton(action: { actionHandler.onToggleComplete(nodeID: entry.id) }) {
          ZStack {
            if showsCollapsedParentMarkerAccent {
              if isMirrorNode {
                RoundedRectangle(
                  cornerRadius: OutlineNodeRowMetrics.collapsedParentCheckboxCornerRadius,
                  style: .continuous
                )
                .stroke(OutlineNodeRowMetrics.collapsedParentMarkerTintColor, lineWidth: 4.25)
                .frame(
                  width: OutlineNodeRowMetrics.checkboxSize + OutlineNodeRowMetrics.collapsedParentCheckboxExpansion,
                  height: OutlineNodeRowMetrics.checkboxSize + OutlineNodeRowMetrics.collapsedParentCheckboxExpansion
                )
                .rotationEffect(.degrees(45))
              } else {
                RoundedRectangle(
                  cornerRadius: OutlineNodeRowMetrics.collapsedParentCheckboxCornerRadius,
                  style: .continuous
                )
                .stroke(OutlineNodeRowMetrics.collapsedParentMarkerTintColor, lineWidth: 4.25)
                .frame(
                  width: OutlineNodeRowMetrics.checkboxSize + OutlineNodeRowMetrics.collapsedParentCheckboxExpansion,
                  height: OutlineNodeRowMetrics.checkboxSize + OutlineNodeRowMetrics.collapsedParentCheckboxExpansion
                )
              }
            }

            if isMirrorNode {
              OutlineCloneTaskCheckbox(isCompleted: completed)
            } else {
              Image(systemName: completed ? "checkmark.square.fill" : "square")
                .font(.system(size: OutlineNodeRowMetrics.checkboxSize))
                .foregroundStyle(OutlineNodeRowMetrics.checkboxTintColor)
            }
          }
        }
      }
      .offset(y: OutlineNodeRowMetrics.checkboxVerticalOffset)
      .contextMenu {
        Button("줌인") { actionHandler.onZoomIn(nodeID: entry.id) }
        Button("미러") { actionHandler.onCopyBlockReference(nodeID: entry.id) }
        Button("선택 미러") { actionHandler.onCopySelectedBlockReferences() }
        Button("불렛으로 변환") { actionHandler.onToggleType(nodeID: entry.id) }
        Button("파일 첨부") { actionHandler.onAddAttachment(nodeID: entry.id) }
        Divider()
        Button("삭제", role: .destructive) { actionHandler.onDeleteSubtree(nodeID: entry.id) }
      }
    case .reference(let targetID):
      draggableMarker {
        markerFrame {
          Image(systemName: "arrow.turn.up.right")
            .font(.system(size: 10))
            .foregroundStyle(.purple)
        }
      }
      .offset(y: OutlineNodeRowMetrics.markerVerticalOffset)
      .contextMenu {
        Button("미러") { actionHandler.onCopyBlockReference(nodeID: entry.id) }
        Button("선택 미러") { actionHandler.onCopySelectedBlockReferences() }
        Button("원본으로 이동") {
          actionHandler.onNavigateToReference(
            targetID: targetID,
            projectID: entry.node.referenceProjectID
          )
        }
        Button("불렛으로 변환") {
          actionHandler.onConvertReferenceToBullet(nodeID: entry.id)
        }
      }
    }
  }

  private func markerButton<Content: View>(
    action: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Button(action: action) {
      markerFrame(content: content)
    }
    .buttonStyle(.plain)
  }

  private func markerFrame<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    ZStack {
      content()
    }
    .frame(
      width: OutlineNodeRowMetrics.bulletAreaWidth,
      height: OutlineNodeRowMetrics.firstLineMarkerSlotHeight,
      alignment: .center
    )
    .contentShape(Rectangle())
  }

  private func draggableMarker<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .draggable(dragTransfer)
  }
}

// MARK: - Breadcrumb

struct OutlineProjectHeading: View {
  private let horizontalShift: CGFloat = 30
  private let topPadding: CGFloat = 20
  private let iconVerticalOffset: CGFloat = -15
  private let titleVerticalOffset: CGFloat = -15
  let title: String
  let accentColor: NSColor
  let selectedStage: ProjectProgressStage
  let topFadeHeight: CGFloat
  let usesIntrinsicFadeMask: Bool
  let onUpdateTitle: (String) -> Void
  let onTitleFocusAttempt: () -> Void
  let onTitleFocusChange: (Bool) -> Void
  let onSelectStage: (ProjectProgressStage) -> Void

  @State private var draftTitle: String
  @State private var isEditingTitle = false
  @FocusState private var isTitleFocused: Bool

  private var accentSwiftUIColor: Color {
    Color(nsColor: accentColor)
  }

  private var titleFont: NSFont {
    OutlinerFonts.exactNSFont(size: 26, weight: .bold)
  }

  private var titleDisplayFont: Font {
    .custom(titleFont.fontName, size: titleFont.pointSize)
  }

  private var leadingOffsetWidth: CGFloat {
    max(0, OutlineRowLayoutSpec.leadingTextX(depth: 0) - horizontalShift)
  }

  private var titleFieldHeight: CGFloat {
    max(
      OutlineNodeRowMetrics.rowMinHeight,
      ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
    )
  }

  private var resolvedDisplayTitle: String {
    let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? OutlinerProject.defaultTitle : trimmed
  }

  private var titleFadeMaskHeight: CGFloat {
    topFadeHeight + 10
  }

  init(
    title: String,
    accentColor: NSColor,
    selectedStage: ProjectProgressStage,
    topFadeHeight: CGFloat = OutlinerCanvasMetrics.topFadeHeight,
    usesIntrinsicFadeMask: Bool = true,
    onUpdateTitle: @escaping (String) -> Void,
    onTitleFocusAttempt: @escaping () -> Void,
    onTitleFocusChange: @escaping (Bool) -> Void,
    onSelectStage: @escaping (ProjectProgressStage) -> Void
  ) {
    self.title = title
    self.accentColor = accentColor
    self.selectedStage = selectedStage
    self.topFadeHeight = topFadeHeight
    self.usesIntrinsicFadeMask = usesIntrinsicFadeMask
    self.onUpdateTitle = onUpdateTitle
    self.onTitleFocusAttempt = onTitleFocusAttempt
    self.onTitleFocusChange = onTitleFocusChange
    self.onSelectStage = onSelectStage
    _draftTitle = State(initialValue: title)
  }

  private func commitTitleIfNeeded() {
    let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedTitle = trimmed.isEmpty ? OutlinerProject.defaultTitle : trimmed
    if draftTitle != resolvedTitle {
      draftTitle = resolvedTitle
    }
    guard resolvedTitle != title else { return }
    onUpdateTitle(resolvedTitle)
  }

  private func startTitleEditing() {
    onTitleFocusAttempt()
    isEditingTitle = true
    DispatchQueue.main.async {
      isTitleFocused = true
    }
  }

  private func finishTitleEditing() {
    commitTitleIfNeeded()
    isEditingTitle = false
  }

  private var headingContent: some View {
    HStack(alignment: .top, spacing: 0) {
      Spacer()
        .frame(width: leadingOffsetWidth)
      LeftClickMenuButton(
        selectedStage: selectedStage,
        onSelect: onSelectStage
      ) {
        Image(systemName: selectedStage.iconName)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(accentSwiftUIColor)
          .frame(width: 36, height: 36)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(accentSwiftUIColor.opacity(0.12))
        )
      }
      .frame(width: 44, alignment: .leading)
      .padding(.top, 1)
      .padding(.trailing, 12)
      .offset(y: iconVerticalOffset)

      Group {
        if isEditingTitle {
          TextField("", text: $draftTitle, prompt: Text(OutlinerProject.defaultTitle))
            .textFieldStyle(.plain)
            .font(titleDisplayFont)
            .foregroundStyle(accentSwiftUIColor)
            .focused($isTitleFocused)
            .onSubmit {
              finishTitleEditing()
            }
        } else {
          Text(resolvedDisplayTitle)
            .font(titleDisplayFont)
            .foregroundStyle(accentSwiftUIColor)
            .lineLimit(1)
            .contentShape(Rectangle())
            .onTapGesture {
              startTitleEditing()
            }
        }
      }
        .onChange(of: title) { _, newValue in
          if !isEditingTitle && draftTitle != newValue {
            draftTitle = newValue
          }
        }
        .onChange(of: isTitleFocused) { _, focused in
          onTitleFocusChange(focused)
          if isEditingTitle && !focused {
            finishTitleEditing()
          }
        }
        .frame(
          maxWidth: .infinity,
          minHeight: titleFieldHeight,
          maxHeight: titleFieldHeight,
          alignment: .leading
        )
        .offset(y: titleVerticalOffset)
    }
    .padding(.top, topPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  var body: some View {
    if usesIntrinsicFadeMask {
      headingContent
        .compositingGroup()
        .mask(alignment: .top) {
          VStack(spacing: 0) {
            LinearGradient(
              stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.92), location: 0.62),
                .init(color: .black, location: 1)
              ],
              startPoint: .top,
              endPoint: .bottom
            )
            .frame(height: titleFadeMaskHeight)

            Rectangle()
              .fill(Color.black)
          }
        }
    } else {
      headingContent
    }
  }
}

struct OutlineScrollTopFadeOverlay: View {
  let fadeHeight: CGFloat

  var body: some View {
    LinearGradient(
      colors: [Color.white, Color.white.opacity(0)],
      startPoint: .top,
      endPoint: .bottom
    )
    .frame(height: fadeHeight)
    .frame(maxWidth: .infinity, alignment: .top)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct OutlineBreadcrumbWrapLayout: Layout {
  let itemSpacing: CGFloat
  let lineSpacing: CGFloat

  private struct Row {
    var items: [(index: Int, size: CGSize)] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) -> CGSize {
    let rows = rows(for: subviews, maxWidth: proposal.width)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.reduce(CGFloat.zero) { partial, row in
      partial + row.height
    } + max(0, CGFloat(rows.count - 1) * lineSpacing)
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) {
    let rows = rows(for: subviews, maxWidth: bounds.width > 0 ? bounds.width : proposal.width)
    var y = bounds.minY

    for row in rows {
      var x = bounds.minX
      for item in row.items {
        let origin = CGPoint(
          x: x,
          y: y + ((row.height - item.size.height) / 2)
        )
        subviews[item.index].place(at: origin, proposal: ProposedViewSize(item.size))
        x += item.size.width + itemSpacing
      }
      y += row.height + lineSpacing
    }
  }

  private func rows(for subviews: Subviews, maxWidth proposedWidth: CGFloat?) -> [Row] {
    let maxWidth = max(
      proposedWidth ?? .greatestFiniteMagnitude,
      1
    )
    var rows: [Row] = []
    var currentRow = Row()

    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      let nextWidth = currentRow.items.isEmpty
        ? size.width
        : currentRow.width + itemSpacing + size.width

      if !currentRow.items.isEmpty && nextWidth > maxWidth {
        rows.append(currentRow)
        currentRow = Row()
      }

      currentRow.items.append((index: index, size: size))
      currentRow.width = currentRow.items.count == 1
        ? size.width
        : currentRow.width + itemSpacing + size.width
      currentRow.height = max(currentRow.height, size.height)
    }

    if !currentRow.items.isEmpty {
      rows.append(currentRow)
    }

    return rows
  }
}

private struct OutlineBreadcrumbCrumb: View {
  let text: String
  let isProject: Bool
  let showsSeparator: Bool
  let action: () -> Void

  var body: some View {
    HStack(spacing: OutlinerCanvasMetrics.breadcrumbItemSpacing) {
      if showsSeparator {
        Text("/")
          .font(.sandoll(size: 13))
          .foregroundStyle(Color.secondary.opacity(0.7))
      }

      Button(action: action) {
        Text(text)
          .font(.sandoll(size: 13, weight: isProject ? .medium : .regular))
          .foregroundStyle(Color.primary.opacity(isProject ? 0.95 : 0.82))
          .lineLimit(1)
      }
      .buttonStyle(.plain)
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}

struct OutlineBreadcrumb: View {
  let path: [OutlineBreadcrumbItem]
  let onNavigate: (UUID?) -> Void

  var body: some View {
    OutlineBreadcrumbWrapLayout(
      itemSpacing: OutlinerCanvasMetrics.breadcrumbItemSpacing,
      lineSpacing: OutlinerCanvasMetrics.breadcrumbLineSpacing
    ) {
      ForEach(Array(path.enumerated()), id: \.element.identifier) { element in
        OutlineBreadcrumbCrumb(
          text: element.element.text,
          isProject: element.element.isProject,
          showsSeparator: element.offset > 0
        ) {
          onNavigate(element.element.id)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
