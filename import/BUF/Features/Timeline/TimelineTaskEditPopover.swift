import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TimelineTaskEditTarget: Equatable, Sendable {
  let projectID: UUID
  let taskID: UUID
}

struct WorkspaceTaskEditPanelTarget: Equatable, Sendable {
  let projectID: UUID
  let taskID: UUID
  let initialFields: RetainedTaskEditFields
}

enum TaskEditReloadToken {
  static func workspacePanel(
    projectID: UUID,
    taskID: UUID,
    workspaceTreeRevision: Int
  ) -> String {
    "\(projectID.uuidString)-\(taskID.uuidString)-\(workspaceTreeRevision)"
  }
}

enum TaskEditSyncSessionID {
  static func workspacePanel(projectID: UUID, taskID: UUID) -> String {
    "workspace-task-edit-\(projectID.uuidString)-\(taskID.uuidString)"
  }
}

enum TimelineTaskEditPresentationStyle {
  case popover
  case panel
  case inlinePanel
}

private struct PendingAttachmentRename: Identifiable, Equatable {
  let attachment: TaskEditAttachment

  var id: String { attachment.id }
  var originalNameStem: String {
    TaskEditAttachmentService.editableFilenameStem(for: attachment)
  }
  var fixedExtension: String? {
    let value = attachment.fileURL.pathExtension
    return value.isEmpty ? nil : value
  }
}

struct TimelineTaskEditPopoverContent: View {
  let initialFields: RetainedTaskEditFields
  let presentationStyle: TimelineTaskEditPresentationStyle
  let reloadToken: String
  let vaultRootURL: URL?
  let loadFields: () async -> RetainedTaskEditFields
  let saveFields: (RetainedTaskEditFields) async throws -> Void
  let onSyncEditingChanged: (Bool) -> Void
  let onSyncEditingActivity: () -> Void
  let bottomContent: AnyView?
  let closeRequestID: Int
  let onCancel: () -> Void

  @State private var title: String
  @State private var noteText: String
  @State private var attachments: [TaskEditAttachment]
  @State private var titleHeight: CGFloat = TaskEditTypography.titleMinimumHeight
  @State private var noteHeight: CGFloat = TaskEditTypography.noteMinimumHeight
  @State private var hasDate: Bool
  @State private var selectedDate: Date
  @State private var hasTime: Bool
  @State private var selectedTime: Date
  @State private var durationMinutes: Int?
  @State private var isDatePickerPresented = false
  @State private var isTimePickerPresented = false
  @State private var lastCommittedFields: RetainedTaskEditFields
  @State private var autoSaveTask: Task<Void, Never>?
  @State private var saveAgainAfterCurrent = false
  @State private var isLoading = false
  @State private var isSaving = false
  @State private var isAttachmentDropTargeted = false
  @State private var isImportingAttachments = false
  @State private var pendingAttachmentDelete: TaskEditAttachment?
  @State private var pendingAttachmentRename: PendingAttachmentRename?
  @State private var errorText: String?
  @State private var isSyncEditingActive = false
  @State private var isClosing = false
  @State private var skipCleanReloadAfterLocalSaveUntil: Date?

  private let calendar = Calendar.autoupdatingCurrent
  private static let autoSaveDelayNanoseconds: UInt64 = 1_200_000_000
  private static let localSaveReloadSkipWindow: TimeInterval = 2

  init(
    initialFields: RetainedTaskEditFields,
    presentationStyle: TimelineTaskEditPresentationStyle = .popover,
    reloadToken: String = "initial",
    vaultRootURL: URL? = nil,
    loadFields: @escaping () async -> RetainedTaskEditFields,
    saveFields: @escaping (RetainedTaskEditFields) async throws -> Void,
    onSyncEditingChanged: @escaping (Bool) -> Void = { _ in },
    onSyncEditingActivity: @escaping () -> Void = {},
    bottomContent: AnyView? = nil,
    closeRequestID: Int = 0,
    onCancel: @escaping () -> Void
  ) {
    let initialNoteText = TaskEditAttachmentService.noteTextByRemovingAttachmentLinks(
      from: initialFields.noteText
    )
    let initialAttachments = TaskEditAttachmentService.attachments(
      in: initialFields.noteText,
      vaultRootURL: vaultRootURL
    )
    self.initialFields = initialFields
    self.presentationStyle = presentationStyle
    self.reloadToken = reloadToken
    self.vaultRootURL = vaultRootURL
    self.loadFields = loadFields
    self.saveFields = saveFields
    self.onSyncEditingChanged = onSyncEditingChanged
    self.onSyncEditingActivity = onSyncEditingActivity
    self.bottomContent = bottomContent
    self.closeRequestID = closeRequestID
    self.onCancel = onCancel
    _title = State(initialValue: initialFields.title)
    _noteText = State(initialValue: initialNoteText)
    _attachments = State(initialValue: initialAttachments)
    _hasDate = State(initialValue: initialFields.day != nil)
    _selectedDate = State(initialValue: initialFields.day ?? .now)
    _hasTime = State(initialValue: initialFields.timeMinutes != nil)
    _selectedTime = State(initialValue: Self.timeDate(minutes: initialFields.timeMinutes))
    _durationMinutes = State(initialValue: initialFields.durationMinutes)
    _lastCommittedFields = State(
      initialValue: Self.savingFields(
        title: initialFields.title,
        noteText: initialNoteText,
        attachments: initialAttachments,
        day: initialFields.day,
        timeMinutes: initialFields.timeMinutes,
        durationMinutes: initialFields.durationMinutes
      )
    )
  }

  var body: some View {
    styledContent
      .alert(item: $pendingAttachmentDelete) { attachment in
        Alert(
          title: Text("첨부파일 삭제"),
          message: Text(
            "\(attachment.displayName)을 삭제합니다. 이 작업은 앱에서 되돌릴 수 없습니다. 파일은 macOS 휴지통으로 이동합니다."
          ),
          primaryButton: .destructive(Text("삭제")) {
            deleteAttachment(attachment)
          },
          secondaryButton: .cancel(Text("취소")) {
            pendingAttachmentDelete = nil
          }
        )
      }
      .sheet(item: $pendingAttachmentRename) { request in
        WorkspaceRenameAttachmentSheetContent(
          originalNameStem: request.originalNameStem,
          fixedExtension: request.fixedExtension,
          isRenaming: false,
          onSubmit: { name in
            renameAttachment(request.attachment, rawStem: name)
          },
          onCancel: {
            pendingAttachmentRename = nil
          }
        )
      }
      .onChange(of: hasDate) { _, enabled in
        if !enabled {
          hasTime = false
          isDatePickerPresented = false
          isTimePickerPresented = false
        }
        scheduleAutoSave()
      }
      .onChange(of: hasTime) { _, _ in
        if !hasTime {
          isTimePickerPresented = false
        }
        scheduleAutoSave()
      }
      .onChange(of: selectedDate) { _, _ in
        scheduleAutoSave()
      }
      .onChange(of: selectedTime) { _, _ in
        scheduleAutoSave()
      }
      .onChange(of: title) { _, _ in
        scheduleAutoSave()
      }
      .onChange(of: noteText) { _, _ in
        scheduleAutoSave()
      }
      .onChange(of: attachments) { _, _ in
        scheduleAutoSave()
      }
      .onExitCommand {
        closeEditor()
      }
      .onChange(of: closeRequestID) { _, requestID in
        guard requestID > 0 else { return }
        closeEditor()
      }
      .task(id: reloadToken) {
        await loadLatest()
      }
      .onDisappear {
        flushPendingChangesOnDisappear()
        endSyncEditingSession()
      }
  }

  @ViewBuilder
  private var styledContent: some View {
    switch presentationStyle {
    case .popover:
      formContent
        .padding(12)
        .frame(width: 340, alignment: .topLeading)
        .overlaySurface(
          cornerRadius: 12,
          fillColor: Color(nsColor: NSColor(calibratedWhite: 0.985, alpha: 1)),
          strokeColor: .secondary,
          style: .card()
        )
    case .panel:
      ScrollView {
        formContent
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .background(TaskEditFieldStyle.panelBackgroundColor)
      }
      .background(TaskEditFieldStyle.panelBackgroundColor)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    case .inlinePanel:
      formContent
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TaskEditFieldStyle.panelBackgroundColor)
    }
  }

  private var formContent: some View {
    VStack(alignment: .leading, spacing: 13) {
      if presentationStyle != .inlinePanel {
        HStack(spacing: 8) {
          Spacer(minLength: 0)
          if isLoading || isSaving {
            ProgressView()
              .controlSize(.small)
          }
          Button {
            closeEditor()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 14, weight: .semibold))
              .frame(width: 28, height: 28)
          }
          .buttonStyle(.plain)
          .help("닫기")
        }
      }

      if presentationStyle != .inlinePanel {
        VStack(alignment: .leading, spacing: 6) {
          Text("제목")
            .font(TaskEditTypography.labelFont)
            .foregroundStyle(.secondary)
          LinkedTextEditor(
            text: $title,
            measuredHeight: $titleHeight,
            font: TaskEditTypography.titleNSFont,
            vaultRootURL: vaultRootURL,
            allowsNewlines: false,
            lineHeightMultiple: 1,
            onEscape: closeEditor
          )
          .frame(minHeight: TaskEditTypography.titleMinimumHeight)
          .frame(height: max(TaskEditTypography.titleMinimumHeight, titleHeight))
          .taskEditFieldBackground(cornerRadius: 4, topPadding: 8, bottomPadding: 4)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        if presentationStyle != .inlinePanel {
          Text("내용")
            .font(TaskEditTypography.labelFont)
            .foregroundStyle(.secondary)
        }
        LinkedTextEditor(
          text: $noteText,
          measuredHeight: $noteHeight,
          font: TaskEditTypography.noteNSFont,
          vaultRootURL: vaultRootURL,
          allowsNewlines: true,
          lineHeightMultiple: 1.1,
          markdownPresentationMode: .livePreview,
          allowsMailMessageDrops: true,
          trailingInputReserveLineCount: noteTrailingInputReserveLineCount,
          trailingInputReserveActivationHeight: TaskEditTypography.noteMinimumHeight,
          onEscape: closeEditor
        )
        .frame(minHeight: TaskEditTypography.noteMinimumHeight)
        .frame(height: max(TaskEditTypography.noteMinimumHeight, noteHeight))
        .taskEditFieldBackground(cornerRadius: 4)
      }

      attachmentSection

      dateTimeSection

      if let bottomContent {
        VStack(alignment: .leading, spacing: 10) {
          Divider()
          bottomContent
        }
        .padding(.top, 4)
      }

      if let errorText {
        Text(errorText)
          .font(TaskEditTypography.labelFont)
          .foregroundStyle(.red)
          .lineLimit(2)
      }

    }
  }

  private var dateTimeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        Toggle("날짜", isOn: $hasDate)
          .toggleStyle(.checkbox)
          .font(TaskEditTypography.controlFont)
          .frame(width: 88, alignment: .leading)

        Button {
          if !hasDate {
            hasDate = true
          }
          isDatePickerPresented = true
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "calendar")
              .font(.system(size: 13, weight: .semibold))
            Text(hasDate ? selectedDateText : "날짜 없음")
              .font(TaskEditTypography.controlFont)
              .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.secondary)
          }
          .taskEditCompactControlBackground()
        }
        .buttonStyle(.plain)
        .foregroundStyle(hasDate ? Color.primary : Color.secondary)
        .popover(isPresented: $isDatePickerPresented, arrowEdge: .bottom) {
          DatePicker("", selection: $selectedDate, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(12)
            .frame(width: 284, alignment: .leading)
            .background(TaskEditFieldStyle.panelBackgroundColor)
        }
      }

      HStack(alignment: .center, spacing: 10) {
        Toggle("시간", isOn: $hasTime)
          .toggleStyle(.checkbox)
          .font(TaskEditTypography.controlFont)
          .disabled(!hasDate)
          .frame(width: 88, alignment: .leading)

        Button {
          guard hasDate else { return }
          if !hasTime {
            hasTime = true
          }
          isTimePickerPresented = true
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "clock")
              .font(.system(size: 13, weight: .semibold))
            Text(hasDate && hasTime ? selectedTimeText : "시간 없음")
              .font(TaskEditTypography.controlFont)
              .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.secondary)
          }
          .taskEditCompactControlBackground()
        }
        .buttonStyle(.plain)
        .foregroundStyle(hasDate && hasTime ? Color.primary : Color.secondary)
        .disabled(!hasDate)
        .popover(isPresented: $isTimePickerPresented, arrowEdge: .bottom) {
          DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.compact)
            .padding(12)
            .frame(width: 148, alignment: .leading)
            .background(TaskEditFieldStyle.panelBackgroundColor)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .tint(TaskEditFieldStyle.softAccentColor)
  }

  private var attachmentSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("첨부파일")
        .font(TaskEditTypography.labelFont)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 7) {
        ForEach(attachmentItems) { attachment in
          HStack(spacing: 8) {
            Button {
              NSWorkspace.shared.open(attachment.fileURL)
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "paperclip")
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(.secondary)
                Text(attachment.displayName)
                  .font(TaskEditTypography.controlFont)
                  .lineLimit(1)
                Spacer(minLength: 0)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
              pendingAttachmentDelete = attachment
            } label: {
              Text("x")
                .font(TaskEditTypography.buttonFont)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("첨부파일 삭제")
          }
          .onDrag {
            attachmentItemProvider(for: attachment)
          }
          .contextMenu {
            Button {
              pendingAttachmentRename = PendingAttachmentRename(attachment: attachment)
            } label: {
              Label("이름 변경", systemImage: "pencil")
            }
          }
          .padding(.vertical, 2)
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        Text(isImportingAttachments ? "첨부파일 복사 중..." : "파일을 여기에 드래그")
          .font(TaskEditTypography.controlFont)
          .foregroundStyle(isAttachmentDropTargeted ? Color.accentColor : Color.secondary)
          .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
          .background(
            Rectangle()
              .fill(
                isAttachmentDropTargeted
                  ? Color.accentColor.opacity(0.07)
                  : Color(nsColor: .controlBackgroundColor).opacity(0.62)
              )
          )
          .overlay(
            Rectangle()
              .stroke(
                isAttachmentDropTargeted
                  ? Color.accentColor.opacity(0.65)
                  : Color.secondary.opacity(0.22),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
              )
          )
          .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isAttachmentDropTargeted
          ) { providers in
            Task {
              await importDroppedAttachmentProviders(providers)
            }
            return true
          }
      }
    }
  }

  private var attachmentItems: [TaskEditAttachment] {
    attachments
  }

  private var noteTrailingInputReserveLineCount: Int {
    presentationStyle == .inlinePanel ? 2 : 0
  }

  private var selectedDateText: String {
    selectedDate.formatted(.dateTime.year().month(.wide).day())
  }

  private var selectedTimeText: String {
    selectedTime.formatted(.dateTime.hour().minute())
  }

  private func attachmentItemProvider(for attachment: TaskEditAttachment) -> NSItemProvider {
    let exportFilename = TaskEditAttachmentService.exportFilename(for: attachment)
    let exportURL =
      try? ApplePlatformDragBridge.shared.materializeFileExport(
        sourceURL: attachment.fileURL,
        displayFilename: exportFilename,
        exportID: UUID()
      )
    let provider =
      NSItemProvider(contentsOf: exportURL ?? attachment.fileURL)
      ?? NSItemProvider(object: (exportURL ?? attachment.fileURL) as NSURL)
    provider.suggestedName = TaskEditAttachmentService.exportSuggestedName(for: attachment)
    return provider
  }

  @MainActor
  private func importDroppedAttachmentProviders(_ providers: [NSItemProvider]) async {
    guard !providers.isEmpty else { return }
    isImportingAttachments = true
    errorText = nil
    defer {
      isImportingAttachments = false
    }
    do {
      let sourceURLs = try await TaskEditAttachmentDropLoader.fileURLs(from: providers)
      let vaultRootURL = vaultRootURL
      let importedAttachments = try await Task.detached {
        try TaskEditAttachmentService.copyFilesToRawAssets(
          sourceURLs: sourceURLs,
          vaultRootURL: vaultRootURL
        )
      }.value
      attachments.append(contentsOf: importedAttachments)
      markSyncEditingActivity()
      autoSaveTask?.cancel()
      autoSaveTask = nil
      _ = await savePendingChanges(afterCurrent: true)
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func deleteAttachment(_ attachment: TaskEditAttachment) {
    do {
      try TaskEditAttachmentService.deleteAttachment(
        attachment,
        vaultRootURL: vaultRootURL
      )
      attachments.removeAll { $0.id == attachment.id }
      pendingAttachmentDelete = nil
      errorText = nil
      markSyncEditingActivity()
      autoSaveTask?.cancel()
      autoSaveTask = nil
      Task { @MainActor in
        _ = await savePendingChanges(afterCurrent: true)
      }
    } catch {
      pendingAttachmentDelete = nil
      errorText = error.localizedDescription
      }
  }

  private func renameAttachment(_ attachment: TaskEditAttachment, rawStem: String) {
    guard let index = attachments.firstIndex(where: { $0.id == attachment.id }),
      let displayName = TaskEditAttachmentService.renamedDisplayName(
        for: attachments[index],
        rawStem: rawStem
      )
    else {
      pendingAttachmentRename = nil
      return
    }

    guard displayName != attachments[index].displayName else {
      pendingAttachmentRename = nil
      return
    }

    let current = attachments[index]
    attachments[index] = TaskEditAttachment(
      displayName: displayName,
      relativePath: current.relativePath,
      fileURL: current.fileURL
    )
    pendingAttachmentRename = nil
    errorText = nil
    markSyncEditingActivity()
    autoSaveTask?.cancel()
    autoSaveTask = nil
    Task { @MainActor in
      _ = await savePendingChanges(afterCurrent: true)
    }
  }

  private func loadLatest() async {
    let current = currentFields()
    guard current == lastCommittedFields else {
      return
    }
    let now = Date()
    if TimelineTaskEditReloadPolicy.shouldSkipCleanReloadAfterLocalSave(
      current: current,
      lastCommitted: lastCommittedFields,
      skipUntil: skipCleanReloadAfterLocalSaveUntil,
      now: now
    ) {
      skipCleanReloadAfterLocalSaveUntil = nil
      return
    }
    if let skipUntil = skipCleanReloadAfterLocalSaveUntil, now > skipUntil {
      skipCleanReloadAfterLocalSaveUntil = nil
    }

    isLoading = true
    defer { isLoading = false }
    let fields = await loadFields()
    let latestCurrent = currentFields()
    guard latestCurrent == lastCommittedFields else {
      return
    }
    let loadedFields = committedFields(from: fields)
    guard !TimelineTaskEditReloadPolicy.shouldPreserveCurrentEditorFields(
      current: latestCurrent,
      loaded: loadedFields
    ) else {
      return
    }
    apply(fields, committedFields: loadedFields)
  }

  private func apply(_ fields: RetainedTaskEditFields, committedFields: RetainedTaskEditFields? = nil) {
    autoSaveTask?.cancel()
    autoSaveTask = nil
    let nextNoteText = TaskEditAttachmentService.noteTextByRemovingAttachmentLinks(from: fields.noteText)
    let nextAttachments = TaskEditAttachmentService.attachments(in: fields.noteText, vaultRootURL: vaultRootURL)
    title = fields.title
    noteText = nextNoteText
    attachments = nextAttachments
    hasDate = fields.day != nil
    selectedDate = fields.day ?? .now
    hasTime = fields.timeMinutes != nil
    selectedTime = Self.timeDate(minutes: fields.timeMinutes)
    durationMinutes = fields.durationMinutes
    lastCommittedFields =
      committedFields
      ?? Self.savingFields(
        title: fields.title,
        noteText: nextNoteText,
        attachments: nextAttachments,
        day: fields.day,
        timeMinutes: fields.timeMinutes,
        durationMinutes: fields.durationMinutes
      )
    endSyncEditingSessionIfClean()
  }

  private func committedFields(from fields: RetainedTaskEditFields) -> RetainedTaskEditFields {
    let nextNoteText = TaskEditAttachmentService.noteTextByRemovingAttachmentLinks(from: fields.noteText)
    let nextAttachments = TaskEditAttachmentService.attachments(in: fields.noteText, vaultRootURL: vaultRootURL)
    return Self.savingFields(
      title: fields.title,
      noteText: nextNoteText,
      attachments: nextAttachments,
      day: fields.day,
      timeMinutes: fields.timeMinutes,
      durationMinutes: fields.durationMinutes
    )
  }

  private func closeEditor() {
    guard !isClosing else { return }
    isClosing = true
    Task { @MainActor in
      let didFlush = await flushPendingChanges()
      isClosing = false
      guard didFlush else { return }
      onCancel()
    }
  }

  @MainActor
  private func scheduleAutoSave() {
    let fields = currentFields()
    guard shouldSave(fields) else {
      endSyncEditingSessionIfClean()
      return
    }
    markSyncEditingActivity()
    autoSaveTask?.cancel()
    autoSaveTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: Self.autoSaveDelayNanoseconds)
      } catch {
        return
      }
      autoSaveTask = nil
      _ = await savePendingChanges()
    }
  }

  @MainActor
  private func flushPendingChanges() async -> Bool {
    autoSaveTask?.cancel()
    autoSaveTask = nil
    return await savePendingChanges()
  }

  private func flushPendingChangesOnDisappear() {
    autoSaveTask?.cancel()
    autoSaveTask = nil
    Task { @MainActor in
      _ = await savePendingChanges(afterCurrent: true)
      endSyncEditingSession()
    }
  }

  @MainActor
  private func savePendingChanges(afterCurrent: Bool = false) async -> Bool {
    guard !isSaving else {
      if afterCurrent {
        saveAgainAfterCurrent = true
      } else {
        scheduleAutoSave()
      }
      return true
    }
    let fields = currentFields()
    guard shouldSave(fields) else {
      endSyncEditingSessionIfClean()
      return true
    }
    markSyncEditingActivity()
    isSaving = true
    errorText = nil
    do {
      try await saveFields(fields)
      lastCommittedFields = fields
      skipCleanReloadAfterLocalSaveUntil = Date()
        .addingTimeInterval(Self.localSaveReloadSkipWindow)
      isSaving = false
      let shouldSaveImmediately = saveAgainAfterCurrent
      saveAgainAfterCurrent = false
      if shouldSaveImmediately {
        return await savePendingChanges(afterCurrent: true)
      }
      if currentFields() != fields {
        scheduleAutoSave()
      } else {
        endSyncEditingSession()
      }
      return true
    } catch {
      isSaving = false
      saveAgainAfterCurrent = false
      errorText = error.localizedDescription
      endSyncEditingSession()
      return false
    }
  }

  private func markSyncEditingActivity() {
    onSyncEditingActivity()
    guard !isSyncEditingActive else { return }
    isSyncEditingActive = true
    onSyncEditingChanged(true)
  }

  private func endSyncEditingSessionIfClean() {
    guard currentFields() == lastCommittedFields, !isSaving, autoSaveTask == nil else {
      return
    }
    endSyncEditingSession()
  }

  private func endSyncEditingSession() {
    guard isSyncEditingActive else { return }
    isSyncEditingActive = false
    onSyncEditingChanged(false)
  }

  private func currentFields() -> RetainedTaskEditFields {
    Self.savingFields(
      title: title,
      noteText: noteText,
      attachments: attachments,
      day: hasDate ? calendar.startOfDay(for: selectedDate) : nil,
      timeMinutes: hasDate && hasTime ? Self.timeMinutes(from: selectedTime) : nil,
      durationMinutes: durationMinutes
    )
  }

  private func shouldSave(_ fields: RetainedTaskEditFields) -> Bool {
    guard fields != lastCommittedFields else { return false }
    return !fields.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func savingFields(
    title: String,
    noteText: String,
    attachments: [TaskEditAttachment],
    day: Date?,
    timeMinutes: Int?,
    durationMinutes: Int?
  ) -> RetainedTaskEditFields {
    RetainedTaskEditFields(
      title: title.replacingOccurrences(of: "\n", with: " "),
      noteText: TaskEditAttachmentService.noteTextByAppendingAttachments(attachments, to: noteText),
      day: day,
      timeMinutes: timeMinutes,
      durationMinutes: durationMinutes
    )
  }

  private static func timeDate(minutes: Int?) -> Date {
    let boundedMinutes = min(max(0, minutes ?? 9 * 60), 23 * 60 + 59)
    return Calendar.autoupdatingCurrent.date(
      bySettingHour: boundedMinutes / 60,
      minute: boundedMinutes % 60,
      second: 0,
      of: .now
    ) ?? .now
  }

  private static func timeMinutes(from date: Date) -> Int {
    let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }
}

enum TimelineTaskEditReloadPolicy {
  static func shouldSkipCleanReloadAfterLocalSave(
    current: RetainedTaskEditFields,
    lastCommitted: RetainedTaskEditFields,
    skipUntil: Date?,
    now: Date
  ) -> Bool {
    guard current == lastCommitted, let skipUntil else { return false }
    return now <= skipUntil
  }

  static func shouldPreserveCurrentEditorFields(
    current: RetainedTaskEditFields,
    loaded: RetainedTaskEditFields
  ) -> Bool {
    guard current != loaded else { return true }
    var normalizedCurrent = current
    var normalizedLoaded = loaded
    normalizedCurrent.noteText = noteTextByDroppingTrailingBlankLines(current.noteText)
    normalizedLoaded.noteText = noteTextByDroppingTrailingBlankLines(loaded.noteText)
    return normalizedCurrent == normalizedLoaded
  }

  private static func noteTextByDroppingTrailingBlankLines(_ noteText: String) -> String {
    var lines = noteText.components(separatedBy: "\n")
    while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
      lines.removeLast()
    }
    return lines.joined(separator: "\n")
  }
}

enum TaskEditTypography {
  static let scale: CGFloat = 1.3
  static let headerSize: CGFloat = 12 * scale
  static let panelTextSize: CGFloat = headerSize * 0.9
  static let labelSize: CGFloat = panelTextSize
  static let bodySize: CGFloat = panelTextSize
  static let titleSize: CGFloat = panelTextSize
  static let titleMinimumHeight: CGFloat = 32
  static let noteMinimumHeight: CGFloat = 150

  static let headerFont = AppInputTypography.font(size: headerSize, weight: .semibold)
  static let labelFont = AppInputTypography.font(size: labelSize)
  static let controlFont = AppInputTypography.font(size: bodySize)
  static let buttonFont = AppInputTypography.font(size: bodySize)

  static var titleNSFont: NSFont {
    AppInputTypography.nsFont(size: titleSize)
  }

  static var noteNSFont: NSFont {
    AppInputTypography.nsFont(size: bodySize)
  }
}

private struct TaskEditFieldBackground: ViewModifier {
  let cornerRadius: CGFloat
  let topPadding: CGFloat
  let bottomPadding: CGFloat

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 12)
      .padding(.top, topPadding)
      .padding(.bottom, bottomPadding)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(TaskEditFieldStyle.backgroundColor)
      )
  }
}

private struct TaskEditCompactControlBackground: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 10)
      .frame(height: 32)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(TaskEditFieldStyle.controlBackgroundColor)
      )
  }
}

private enum TaskEditFieldStyle {
  static let panelBackgroundColor = Color(
    nsColor: NSColor(calibratedWhite: 1, alpha: 1)
  )

  static let backgroundColor = Color(
    nsColor: NSColor(calibratedWhite: 0.975, alpha: 1)
  )

  static let controlBackgroundColor = Color(
    nsColor: NSColor(calibratedWhite: 0.985, alpha: 1)
  )

  static let softAccentColor = Color(
    nsColor: NSColor.systemBlue.withAlphaComponent(0.28)
  )

}

extension View {
  func taskEditFieldBackground(
    cornerRadius: CGFloat,
    topPadding: CGFloat = 8,
    bottomPadding: CGFloat = 8
  ) -> some View {
    modifier(
      TaskEditFieldBackground(
        cornerRadius: cornerRadius,
        topPadding: topPadding,
        bottomPadding: bottomPadding
      )
    )
  }

  func taskEditCompactControlBackground() -> some View {
    modifier(TaskEditCompactControlBackground())
  }
}

@MainActor
private enum TaskEditAttachmentDropLoader {
  static func fileURLs(from providers: [NSItemProvider]) async throws -> [URL] {
    var urls: [URL] = []
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      if let url = try await fileURL(from: provider) {
        urls.append(url)
      }
    }
    return urls
  }

  private static func fileURL(from provider: NSItemProvider) async throws -> URL? {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        continuation.resume(returning: decodeFileURL(from: item))
      }
    }
  }

  nonisolated private static func decodeFileURL(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
      return url
    }
    if let nsURL = item as? NSURL {
      return nsURL as URL
    }
    if let data = item as? Data {
      return URL(dataRepresentation: data, relativeTo: nil)
    }
    if let string = item as? String {
      return URL(string: string) ?? URL(fileURLWithPath: string)
    }
    return nil
  }
}
