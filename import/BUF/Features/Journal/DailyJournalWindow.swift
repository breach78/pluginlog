import AppKit
import SwiftUI

extension NSUserInterfaceItemIdentifier {
  static let dailyJournalWindow = NSUserInterfaceItemIdentifier("dailyJournalWindow")
}

@MainActor
final class DailyJournalWindowPresenter {
  static let shared = DailyJournalWindowPresenter()

  private var window: NSWindow?
  private var delegate: WindowDelegate?

  private init() {}

  func present(vaultRootURL: URL?) {
    if let window, Self.isLiveWindow(window) {
      bringForward(window)
      return
    }

    let hostingController = NSHostingController(
      rootView: DailyJournalWindowContent(vaultRootURL: vaultRootURL)
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.identifier = .dailyJournalWindow
    window.title = "저널"
    window.contentViewController = hostingController
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 420, height: 420)
    window.setFrameAutosaveName("DailyJournalWindow")
    window.center()

    let delegate = WindowDelegate { [weak self] in
      self?.window = nil
      self?.delegate = nil
    }
    window.delegate = delegate
    self.window = window
    self.delegate = delegate

    bringForward(window)
  }

  private func bringForward(_ window: NSWindow) {
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private static func isLiveWindow(_ window: NSWindow) -> Bool {
    window.isVisible || window.isMiniaturized
  }

  private final class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
      self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
      onClose()
    }
  }
}

struct DailyJournalWindowContent: View {
  let vaultRootURL: URL?

  @State private var entries: [DailyJournalEntry] = []
  @State private var loadErrorText: String?
  @State private var isLoadingMore = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if vaultRootURL == nil {
        missingVaultView
      } else {
        journalScrollView
      }
    }
    .frame(minWidth: 420, minHeight: 420, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear {
      loadInitialEntriesIfNeeded()
    }
  }

  private var missingVaultView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Obsidian vault가 설정되지 않았습니다.")
        .font(.system(size: 14, weight: .semibold))
      Text("저널은 vault의 raw/journals 폴더에 저장됩니다.")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var journalScrollView: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(entries) { entry in
          if let store {
            DailyJournalDaySection(entry: entry, store: store)

            Divider()
          }
        }

        loadMoreButton
      }
    }
  }

  private var loadMoreButton: some View {
    VStack(alignment: .center, spacing: 8) {
      if let loadErrorText {
        Text(loadErrorText)
          .font(.system(size: 12))
          .foregroundStyle(.red)
      }

      Button {
        loadMoreEntries()
      } label: {
        HStack(spacing: 6) {
          if isLoadingMore {
            ProgressView()
              .controlSize(.small)
              .scaleEffect(0.7)
          } else {
            Image(systemName: "chevron.down")
              .font(.system(size: 11, weight: .semibold))
          }
          Text("이전 3일 불러오기")
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderless)
      .disabled(isLoadingMore || store == nil)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
  }

  private var store: DailyJournalStore? {
    vaultRootURL.map { DailyJournalStore(vaultRootURL: $0) }
  }

  private func loadInitialEntriesIfNeeded() {
    guard entries.isEmpty, let store else { return }
    do {
      entries = try store.entries(startingAt: Date(), count: 1)
      loadErrorText = nil
    } catch {
      loadErrorText = "저널을 불러오지 못했습니다."
    }
  }

  private func loadMoreEntries() {
    guard !isLoadingMore, let store else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    do {
      let earliestDate = entries.last?.date ?? Date()
      let nextEntries = try store.precedingEntries(before: earliestDate, count: 3)
      let loadedDates = Set(entries.map(\.date))
      entries.append(contentsOf: nextEntries.filter { !loadedDates.contains($0.date) })
      loadErrorText = nil
    } catch {
      loadErrorText = "이전 저널을 불러오지 못했습니다."
    }
  }
}

private struct DailyJournalDaySection: View {
  let entry: DailyJournalEntry
  let store: DailyJournalStore

  @State private var text: String
  @State private var measuredHeight: CGFloat = 0
  @State private var committedText: String
  @State private var autoSaveTask: Task<Void, Never>?
  @State private var isSaving = false
  @State private var saveAgainAfterCurrent = false
  @State private var saveErrorText: String?

  init(entry: DailyJournalEntry, store: DailyJournalStore) {
    self.entry = entry
    self.store = store
    _text = State(initialValue: entry.text)
    _committedText = State(initialValue: DailyJournalTextPolicy.normalized(entry.text))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(DailyJournalDisplayDatePolicy.title(for: entry.date))
          .font(.system(size: 15, weight: .semibold))

        Spacer(minLength: 0)

        if isSaving {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(0.65)
        } else if saveErrorText != nil {
          Image(systemName: "exclamationmark.circle")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.red)
        }
      }

      LinkedTextEditor(
        text: $text,
        measuredHeight: $measuredHeight,
        font: journalFont,
        vaultRootURL: store.vaultRootURL,
        allowsNewlines: true,
        lineHeightMultiple: 1.1,
        markdownPresentationMode: .livePreview,
        allowsMailMessageDrops: true
      )
      .frame(minHeight: minimumEditorHeight)
      .frame(height: max(minimumEditorHeight, measuredHeight))
      .taskEditFieldBackground(cornerRadius: 4)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .onChange(of: text) { _, _ in
      scheduleAutoSave()
    }
    .onDisappear {
      flushAutoSave()
    }
  }

  private var journalFont: NSFont {
    TaskEditTypography.noteNSFont
  }

  private var minimumEditorHeight: CGFloat {
    TaskEditTypography.noteMinimumHeight
  }

  private func scheduleAutoSave() {
    guard DailyJournalTextPolicy.isDirty(currentText: text, committedText: committedText) else {
      autoSaveTask?.cancel()
      autoSaveTask = nil
      saveErrorText = nil
      return
    }

    autoSaveTask?.cancel()
    autoSaveTask = Task { @MainActor in
      do {
        try await Task.sleep(nanoseconds: Self.autoSaveDelayNanoseconds)
      } catch {
        return
      }
      autoSaveTask = nil
      savePendingText()
    }
  }

  private func flushAutoSave() {
    guard isSaving || DailyJournalTextPolicy.isDirty(
      currentText: text,
      committedText: committedText
    ) else { return }
    autoSaveTask?.cancel()
    autoSaveTask = nil
    Task { @MainActor in
      savePendingText(afterCurrent: true)
    }
  }

  @MainActor
  private func savePendingText(afterCurrent: Bool = false) {
    guard !isSaving else {
      if afterCurrent {
        saveAgainAfterCurrent = true
      } else {
        scheduleAutoSave()
      }
      return
    }

    let noteText = DailyJournalTextPolicy.normalized(text)
    guard DailyJournalTextPolicy.isDirty(
      currentText: noteText,
      committedText: committedText
    ) else {
      saveErrorText = nil
      return
    }

    isSaving = true
    saveErrorText = nil
    do {
      let savedEntry = try store.save(noteText, for: entry.date)
      let nextCommittedText = DailyJournalTextPolicy.normalized(savedEntry.text)
      committedText = nextCommittedText
      if DailyJournalTextPolicy.normalized(text) == nextCommittedText {
        text = savedEntry.text
      }
    } catch {
      saveErrorText = "저장 실패"
    }
    isSaving = false

    let shouldSaveAgain = saveAgainAfterCurrent
    saveAgainAfterCurrent = false
    if DailyJournalTextPolicy.isDirty(currentText: text, committedText: committedText) {
      scheduleAutoSave()
    } else if shouldSaveAgain {
      savePendingText(afterCurrent: true)
    }
  }

  private static let autoSaveDelayNanoseconds: UInt64 = 650_000_000
}

private enum DailyJournalDisplayDatePolicy {
  static func title(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}
