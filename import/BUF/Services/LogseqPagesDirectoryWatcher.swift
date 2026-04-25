import Darwin
import Foundation

extension Notification.Name {
  static let logseqProjectPageStoreDidWriteMarkdown = Notification.Name(
    "BrainUnfog.LogseqProjectPageStoreDidWriteMarkdown"
  )
}

enum LogseqProjectPageStoreWriteNotification {
  static let fileURLKey = "fileURL"
}

final class LogseqPagesChangeTracker: @unchecked Sendable {
  struct FileSignature: Equatable, Sendable {
    let modificationTime: TimeInterval
    let fileSize: Int64
  }

  private let fileManager: FileManager
  private let lock = NSLock()
  private var signaturesByURL: [URL: FileSignature] = [:]
  private var appAuthoredSignaturesByURL: [URL: FileSignature] = [:]

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func recordAppAuthoredWrite(to fileURL: URL) {
    guard let signature = signature(for: fileURL) else { return }
    lock.lock()
    defer { lock.unlock() }
    appAuthoredSignaturesByURL[normalized(fileURL)] = signature
  }

  func changedMarkdownFiles(in pagesRootURL: URL) -> [URL] {
    let currentSignatures = currentMarkdownFiles(in: pagesRootURL).compactMap { fileURL
      -> (URL, FileSignature)? in
      let normalizedURL = normalized(fileURL)
      guard let signature = signature(for: normalizedURL) else { return nil }
      return (normalizedURL, signature)
    }
    var nextSignatures: [URL: FileSignature] = [:]
    var changedFiles: [URL] = []

    lock.lock()
    defer { lock.unlock() }

    for (normalizedURL, signature) in currentSignatures {
      nextSignatures[normalizedURL] = signature
      guard signaturesByURL[normalizedURL] != signature else { continue }
      if appAuthoredSignaturesByURL[normalizedURL] == signature {
        appAuthoredSignaturesByURL.removeValue(forKey: normalizedURL)
        continue
      }
      changedFiles.append(normalizedURL)
    }

    signaturesByURL = nextSignatures
    appAuthoredSignaturesByURL = appAuthoredSignaturesByURL.filter { nextSignatures[$0.key] != nil }
    return changedFiles.sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
  }

  private func currentMarkdownFiles(in pagesRootURL: URL) -> [URL] {
    (try? fileManager.contentsOfDirectory(
      at: pagesRootURL,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
      options: []
    ))?.filter { $0.pathExtension.lowercased() == "md" } ?? []
  }

  private func signature(for fileURL: URL) -> FileSignature? {
    guard let values = try? normalized(fileURL).resourceValues(
      forKeys: [.contentModificationDateKey, .fileSizeKey]
    ) else {
      return nil
    }
    return FileSignature(
      modificationTime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
      fileSize: Int64(values.fileSize ?? 0)
    )
  }

  private func normalized(_ fileURL: URL) -> URL {
    fileURL.resolvingSymlinksInPath().standardizedFileURL
  }
}

final class LogseqPagesDirectoryWatcher: @unchecked Sendable {
  typealias ChangeHandler = @MainActor ([URL]) async -> Void
  typealias FastChangeHandler = @MainActor () -> Void

  static let defaultDebounceNanoseconds: UInt64 = 10_000_000_000
  static let defaultFastDebounceNanoseconds: UInt64 = 500_000_000
  static let defaultFastPollingNanoseconds: UInt64 = 750_000_000

  private let pagesRootURL: URL
  private let debounceNanoseconds: UInt64
  private let fastDebounceNanoseconds: UInt64
  private let pollingNanoseconds: UInt64?
  private let fastPollingNanoseconds: UInt64?
  private let tracker: LogseqPagesChangeTracker
  private let pollingTracker: LogseqPagesChangeTracker
  private let fastTracker: LogseqPagesChangeTracker
  private let handler: ChangeHandler
  private let fastHandler: FastChangeHandler?
  private let queue = DispatchQueue(label: "BrainUnfog.LogseqPagesDirectoryWatcher")

  private var fileDescriptor: CInt = -1
  private var source: DispatchSourceFileSystemObject?
  private var debounceWorkItem: DispatchWorkItem?
  private var fastDebounceWorkItem: DispatchWorkItem?
  private var pollingTimer: DispatchSourceTimer?
  private var fastPollingTimer: DispatchSourceTimer?
  private var writeObserver: NSObjectProtocol?

  init(
    pagesRootURL: URL,
    debounceNanoseconds: UInt64 = LogseqPagesDirectoryWatcher.defaultDebounceNanoseconds,
    fastDebounceNanoseconds: UInt64 = LogseqPagesDirectoryWatcher.defaultFastDebounceNanoseconds,
    pollingNanoseconds: UInt64? = LogseqPagesDirectoryWatcher.defaultDebounceNanoseconds,
    fastPollingNanoseconds: UInt64? = LogseqPagesDirectoryWatcher.defaultFastPollingNanoseconds,
    tracker: LogseqPagesChangeTracker = LogseqPagesChangeTracker(),
    pollingTracker: LogseqPagesChangeTracker = LogseqPagesChangeTracker(),
    fastTracker: LogseqPagesChangeTracker = LogseqPagesChangeTracker(),
    fastHandler: FastChangeHandler? = nil,
    handler: @escaping ChangeHandler
  ) {
    self.pagesRootURL = pagesRootURL
    self.debounceNanoseconds = debounceNanoseconds
    self.fastDebounceNanoseconds = fastDebounceNanoseconds
    self.pollingNanoseconds = pollingNanoseconds
    self.fastPollingNanoseconds = fastPollingNanoseconds
    self.tracker = tracker
    self.pollingTracker = pollingTracker
    self.fastTracker = fastTracker
    self.fastHandler = fastHandler
    self.handler = handler
  }

  deinit {
    stop()
  }

  func start() {
    stop()
    _ = tracker.changedMarkdownFiles(in: pagesRootURL)
    _ = pollingTracker.changedMarkdownFiles(in: pagesRootURL)
    _ = fastTracker.changedMarkdownFiles(in: pagesRootURL)
    registerWriteObserver()
    startPollingTimer()
    startFastPollingTimer()

    fileDescriptor = open(pagesRootURL.path, O_EVTONLY)
    guard fileDescriptor >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .extend, .attrib, .rename, .delete],
      queue: queue
    )
    source.setEventHandler { [weak self] in
      self?.scheduleFastScan()
      self?.scheduleDebouncedScan()
    }
    source.setCancelHandler { [fileDescriptor] in
      if fileDescriptor >= 0 {
        close(fileDescriptor)
      }
    }
    self.source = source
    source.resume()
  }

  func stop() {
    debounceWorkItem?.cancel()
    debounceWorkItem = nil
    fastDebounceWorkItem?.cancel()
    fastDebounceWorkItem = nil
    pollingTimer?.cancel()
    pollingTimer = nil
    fastPollingTimer?.cancel()
    fastPollingTimer = nil
    if let writeObserver {
      NotificationCenter.default.removeObserver(writeObserver)
      self.writeObserver = nil
    }
    source?.cancel()
    source = nil
    fileDescriptor = -1
  }

  private func startPollingTimer() {
    guard fastHandler == nil else { return }
    guard let pollingNanoseconds else { return }
    let interval = DispatchTimeInterval.nanoseconds(
      Int(min(pollingNanoseconds, UInt64(Int.max)))
    )
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + interval, repeating: interval)
    timer.setEventHandler { [weak self] in
      self?.scheduleDebouncedScanIfPollingChanged()
    }
    pollingTimer = timer
    timer.resume()
  }

  private func startFastPollingTimer() {
    guard fastHandler != nil, let fastPollingNanoseconds else { return }
    let interval = DispatchTimeInterval.nanoseconds(
      Int(min(fastPollingNanoseconds, UInt64(Int.max)))
    )
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + interval, repeating: interval)
    timer.setEventHandler { [weak self] in
      self?.runFastScan()
    }
    fastPollingTimer = timer
    timer.resume()
  }

  private func registerWriteObserver() {
    writeObserver = NotificationCenter.default.addObserver(
      forName: .logseqProjectPageStoreDidWriteMarkdown,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      guard let fileURL = notification.userInfo?[LogseqProjectPageStoreWriteNotification.fileURLKey] as? URL else {
        return
      }
      self?.tracker.recordAppAuthoredWrite(to: fileURL)
      self?.pollingTracker.recordAppAuthoredWrite(to: fileURL)
      self?.fastTracker.recordAppAuthoredWrite(to: fileURL)
    }
  }

  private func scheduleFastScan() {
    guard fastHandler != nil else { return }
    fastDebounceWorkItem?.cancel()
    let delay = DispatchTimeInterval.nanoseconds(
      Int(min(fastDebounceNanoseconds, UInt64(Int.max)))
    )
    let workItem = DispatchWorkItem { [weak self] in
      self?.runFastScan()
    }
    fastDebounceWorkItem = workItem
    queue.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func scheduleDebouncedScan() {
    debounceWorkItem?.cancel()
    let delay = DispatchTimeInterval.nanoseconds(
      Int(min(debounceNanoseconds, UInt64(Int.max)))
    )
    let workItem = DispatchWorkItem { [weak self] in
      self?.runScan()
    }
    debounceWorkItem = workItem
    queue.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func runFastScan() {
    guard let fastHandler else { return }
    let changedFiles = fastTracker.changedMarkdownFiles(in: pagesRootURL)
    guard !changedFiles.isEmpty else { return }
    scheduleDebouncedScan()
    Task { @MainActor in
      fastHandler()
    }
  }

  private func scheduleDebouncedScanIfPollingChanged() {
    let changedFiles = pollingTracker.changedMarkdownFiles(in: pagesRootURL)
    guard !changedFiles.isEmpty else { return }
    scheduleDebouncedScan()
  }

  private func runScan() {
    let changedFiles = tracker.changedMarkdownFiles(in: pagesRootURL)
    guard !changedFiles.isEmpty else { return }
    Task { @MainActor [handler] in
      await handler(changedFiles)
    }
  }
}
