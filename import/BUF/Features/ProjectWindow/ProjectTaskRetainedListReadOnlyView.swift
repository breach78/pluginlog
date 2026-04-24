import AppKit

private final class ProjectTaskReadOnlyAttachmentRowView: NSView {
  override var isFlipped: Bool { true }

  private let iconView = NSImageView()
  private let filenameField = NSTextField(labelWithString: "")
  private let metadataField = NSTextField(labelWithString: "")

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: 40)
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.borderWidth = 1

    iconView.imageScaling = .scaleProportionallyDown
    iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)

    [filenameField, metadataField].forEach { field in
      field.backgroundColor = .clear
      field.isBordered = false
      field.isEditable = false
      field.lineBreakMode = .byTruncatingTail
      field.usesSingleLineMode = true
      field.maximumNumberOfLines = 1
    }
    metadataField.alignment = .right

    addSubview(iconView)
    addSubview(filenameField)
    addSubview(metadataField)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  func update(
    filename: String,
    metadata: String,
    availability: NoteDisplayAttachmentAvailability,
    fontSize: CGFloat
  ) {
    filenameField.stringValue = filename
    filenameField.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
    filenameField.textColor = .labelColor

    metadataField.stringValue = metadata
    metadataField.font = NSFont.systemFont(ofSize: max(11, fontSize - 1), weight: .medium)
    metadataField.textColor = .secondaryLabelColor
    metadataField.isHidden = metadata.isEmpty

    iconView.image = NSImage(
      systemSymbolName: symbolName(for: availability),
      accessibilityDescription: "첨부"
    )
    iconView.contentTintColor = accentColor(for: availability)

    layer?.backgroundColor = backgroundColor(for: availability).cgColor
    layer?.borderColor = borderColor(for: availability).cgColor
    needsLayout = true
  }

  override func layout() {
    super.layout()

    let insetX: CGFloat = 12
    let iconSize: CGFloat = 14
    let contentSpacing: CGFloat = 10
    let trailingInset: CGFloat = 12
    let metadataSpacing: CGFloat = metadataField.isHidden ? 0 : 10
    let metadataWidth =
      metadataField.isHidden
      ? CGFloat.zero
      : min(
        ceil(metadataField.intrinsicContentSize.width),
        max(56, bounds.width * 0.24)
      )
    let textHeight = ceil(filenameField.intrinsicContentSize.height)
    let iconY = round((bounds.height - iconSize) * 0.5)
    let textY = round((bounds.height - textHeight) * 0.5)
    let filenameX = insetX + iconSize + contentSpacing
    let filenameWidth = max(
      1,
      bounds.width - filenameX - trailingInset - metadataWidth - metadataSpacing
    )

    iconView.frame = CGRect(x: insetX, y: iconY, width: iconSize, height: iconSize)
    filenameField.frame = CGRect(x: filenameX, y: textY, width: filenameWidth, height: textHeight)

    if metadataField.isHidden {
      metadataField.frame = .zero
    } else {
      metadataField.frame = CGRect(
        x: bounds.width - trailingInset - metadataWidth,
        y: textY,
        width: metadataWidth,
        height: textHeight
      )
    }
  }

  private func symbolName(for availability: NoteDisplayAttachmentAvailability) -> String {
    switch availability {
    case .available:
      return "paperclip"
    case .missing:
      return "exclamationmark.triangle"
    case .archived:
      return "archivebox"
    }
  }

  private func accentColor(for availability: NoteDisplayAttachmentAvailability) -> NSColor {
    switch availability {
    case .available:
      return .secondaryLabelColor
    case .missing:
      return .systemOrange
    case .archived:
      return .secondaryLabelColor
    }
  }

  private func backgroundColor(for availability: NoteDisplayAttachmentAvailability) -> NSColor {
    switch availability {
    case .available, .archived:
      return NSColor.controlBackgroundColor.withAlphaComponent(0.72)
    case .missing:
      return NSColor.systemOrange.withAlphaComponent(0.08)
    }
  }

  private func borderColor(for availability: NoteDisplayAttachmentAvailability) -> NSColor {
    switch availability {
    case .available, .archived:
      return NSColor.black.withAlphaComponent(0.04)
    case .missing:
      return NSColor.systemOrange.withAlphaComponent(0.24)
    }
  }
}

private final class ProjectTaskReadOnlyDividerView: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

final class ProjectTaskRetainedListReadOnlyDetailView: NSView {
  override var isFlipped: Bool { true }

  private let contentField = NSTextField(labelWithString: "")
  private let placeholderField = NSTextField(labelWithString: "")
  private let attachmentDividerView = ProjectTaskReadOnlyDividerView(frame: .zero)
  private var attachmentRowViews: [ProjectTaskReadOnlyAttachmentRowView] = []
  private var snapshot: ProjectTaskReadOnlyDetailSnapshot?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    [contentField, placeholderField].forEach { field in
      field.backgroundColor = .clear
      field.isBordered = false
      field.isEditable = false
      field.lineBreakMode = .byWordWrapping
      field.usesSingleLineMode = false
      field.maximumNumberOfLines = 0
      addSubview(field)
    }
    placeholderField.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5)
    attachmentDividerView.wantsLayer = true
    attachmentDividerView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
    attachmentDividerView.isHidden = true
    addSubview(attachmentDividerView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard snapshot != nil, bounds.contains(point) else { return nil }
    return self
  }

  override func scrollWheel(with event: NSEvent) {
    if let scrollView = enclosingScrollView {
      scrollView.scrollWheel(with: event)
      return
    }
    nextResponder?.scrollWheel(with: event)
  }

  func update(snapshot: ProjectTaskReadOnlyDetailSnapshot?) {
    self.snapshot = snapshot
    guard let snapshot else {
      contentField.stringValue = ""
      placeholderField.stringValue = ""
      syncAttachmentRows([], fontSize: 0)
      needsLayout = true
      return
    }

    contentField.attributedStringValue = attributedTextContent(
      snapshot.textBlocks,
      snapshot: snapshot
    )
    syncAttachmentRows(snapshot.attachments, fontSize: snapshot.fontSize)
    placeholderField.attributedStringValue = NSAttributedString(
      string: snapshot.placeholder,
      attributes: [
        .font: NoteTypography.nsFont(size: snapshot.fontSize),
        .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.5),
      ]
    )
    needsLayout = true
  }

  override func layout() {
    super.layout()
    let insetX: CGFloat = 6
    let baseInsetY: CGFloat = 8
    let verticalContentOffset = max(0, min(snapshot?.verticalContentOffset ?? 0, baseInsetY))
    let topInsetY = baseInsetY + verticalContentOffset
    let bottomInsetY = baseInsetY - verticalContentOffset
    let attachmentSpacing: CGFloat = 6
    let contentToAttachmentSpacing: CGFloat = 10
    let availableWidth = max(1, bounds.width - insetX * 2)
    var cursorY = topInsetY
    let minimumNoteBodyHeight = max(0, snapshot?.noteRegionHeight ?? 0 - baseInsetY * 2)
    let hasTextContent = !contentField.attributedStringValue.string
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    let hasAttachments = !attachmentRowViews.isEmpty
    let showsPlaceholder = !hasTextContent && !hasAttachments
    let attachmentHeight =
      hasAttachments
      ? attachmentRowViews.reduce(CGFloat(0)) { partialResult, rowView in
        partialResult + rowView.intrinsicContentSize.height
      } + CGFloat(max(0, attachmentRowViews.count - 1)) * attachmentSpacing
      : 0

    placeholderField.isHidden = !showsPlaceholder

    if !placeholderField.isHidden {
      let size = placeholderField.sizeThatFits(NSSize(width: availableWidth, height: .greatestFiniteMagnitude))
      let resolvedHeight = max(ceil(size.height), minimumNoteBodyHeight)
      placeholderField.frame = CGRect(x: insetX, y: cursorY, width: availableWidth, height: resolvedHeight)
      cursorY += resolvedHeight
    } else {
      placeholderField.frame = .zero
    }

    contentField.isHidden = showsPlaceholder || !hasTextContent
    if !contentField.isHidden {
      let size = contentField.sizeThatFits(NSSize(width: availableWidth, height: .greatestFiniteMagnitude))
      let reservedAttachmentHeight =
        hasAttachments ? attachmentHeight + contentToAttachmentSpacing : 0
      let desiredHeight = max(ceil(size.height), minimumNoteBodyHeight)
      let height = min(max(0, bounds.height - cursorY - bottomInsetY - reservedAttachmentHeight), desiredHeight)
      contentField.frame = CGRect(x: insetX, y: cursorY, width: availableWidth, height: height)
      cursorY += height
    } else {
      contentField.frame = .zero
    }

    if hasAttachments {
      attachmentDividerView.frame = .zero
      attachmentDividerView.isHidden = true
      if hasTextContent {
        cursorY += contentToAttachmentSpacing
      }
      for (index, rowView) in attachmentRowViews.enumerated() {
        let rowHeight = rowView.intrinsicContentSize.height
        let availableHeight = max(0, bounds.height - cursorY - bottomInsetY)
        let resolvedHeight = min(rowHeight, availableHeight)
        rowView.isHidden = resolvedHeight <= 0
        rowView.frame = CGRect(
          x: insetX,
          y: cursorY,
          width: availableWidth,
          height: resolvedHeight
        )
        cursorY += resolvedHeight
        if index < attachmentRowViews.count - 1 {
          cursorY += attachmentSpacing
        }
      }
    } else {
      attachmentDividerView.frame = .zero
      attachmentDividerView.isHidden = true
      for rowView in attachmentRowViews {
        rowView.frame = .zero
        rowView.isHidden = true
      }
    }
  }

  override func mouseDown(with event: NSEvent) {
    snapshot?.onActivate()
    super.mouseDown(with: event)
  }

  private func attributedTextContent(
    _ textBlocks: [String],
    snapshot: ProjectTaskReadOnlyDetailSnapshot
  ) -> NSAttributedString {
    let rendered = NSMutableAttributedString()

    for text in textBlocks {
      if rendered.length > 0 {
        rendered.append(NSAttributedString(string: "\n\n"))
      }

      rendered.append(
        MarkdownLivePreviewStyler.attributedString(
          for: text,
          fontSize: snapshot.fontSize,
          lineSpacing: snapshot.lineSpacing,
          editingParagraphRange: nil
        )
      )
    }

    return rendered
  }

  private func syncAttachmentRows(
    _ attachments: [ProjectTaskReadOnlyAttachmentSnapshot],
    fontSize: CGFloat
  ) {
    while attachmentRowViews.count > attachments.count {
      attachmentRowViews.removeLast().removeFromSuperview()
    }

    while attachmentRowViews.count < attachments.count {
      let rowView = ProjectTaskReadOnlyAttachmentRowView(frame: .zero)
      attachmentRowViews.append(rowView)
      addSubview(rowView)
    }

    for (index, attachment) in attachments.enumerated() {
      attachmentRowViews[index].update(
        filename: attachment.filename,
        metadata: attachmentMetadataText(
          byteSize: attachment.byteSize,
          availability: attachment.availability,
          isLegacy: attachment.isLegacy
        ),
        availability: attachment.availability,
        fontSize: fontSize
      )
      attachmentRowViews[index].isHidden = false
    }
  }

  private func attachmentMetadataText(
    byteSize: Int64?,
    availability: NoteDisplayAttachmentAvailability,
    isLegacy: Bool
  ) -> String {
    switch availability {
    case .available:
      guard let byteSize else {
        return "첨부"
      }
      let sizeText = ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
      return sizeText
    case .missing:
      return "첨부를 찾을 수 없음"
    case .archived:
      return "보관된 첨부"
    }
  }
}
