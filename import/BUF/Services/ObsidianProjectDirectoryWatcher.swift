import Darwin
import CoreServices
import Foundation

extension Notification.Name {
  static let obsidianProjectMarkdownStoreDidWriteMarkdown = Notification.Name(
    "BrainUnfog.ObsidianProjectMarkdownStoreDidWriteMarkdown"
  )
}

enum ObsidianProjectMarkdownStoreWriteNotification {
  static let fileURLKey = "fileURL"
}

final class ObsidianProjectChangeTracker: @unchecked Sendable {
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

  func changedProjectMarkdownFiles(in projectsRootURL: URL) -> [URL] {
    let currentSignatures = currentMarkdownFiles(in: projectsRootURL).compactMap { fileURL
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

  private func currentMarkdownFiles(in projectsRootURL: URL) -> [URL] {
    (try? fileManager.contentsOfDirectory(
      at: projectsRootURL,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
      options: [.skipsPackageDescendants]
    ))?.filter { isDirectMarkdownFile($0, in: projectsRootURL) } ?? []
  }

  private func isDirectMarkdownFile(_ fileURL: URL, in projectsRootURL: URL) -> Bool {
    let resolvedFile = fileURL.standardizedFileURL.resolvingSymlinksInPath()
    let resolvedRoot = projectsRootURL.standardizedFileURL.resolvingSymlinksInPath()
    guard resolvedFile.pathExtension.lowercased() == "md" else { return false }
    return resolvedFile.deletingLastPathComponent() == resolvedRoot
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

final class ObsidianProjectDirectoryWatcher: @unchecked Sendable {
  typealias ChangeHandler = @MainActor ([URL]) async -> Void
  typealias FastChangeHandler = @MainActor () -> Void

  static let defaultDebounceNanoseconds: UInt64 = 10_000_000_000
  static let defaultFastDebounceNanoseconds: UInt64 = 500_000_000
  static let defaultFastPollingNanoseconds: UInt64 = 750_000_000
  static let defaultFastPollingEnabled = false

  private let vaultRootURL: URL
  private let projectsRootURL: URL
  private let debounceNanoseconds: UInt64
  private let fastDebounceNanoseconds: UInt64
  private let pollingNanoseconds: UInt64?
  private let fastPollingNanoseconds: UInt64?
  private let tracker: ObsidianProjectChangeTracker
  private let pollingTracker: ObsidianProjectChangeTracker
  private let fastTracker: ObsidianProjectChangeTracker
  private let handler: ChangeHandler
  private let fastHandler: FastChangeHandler?
  private let queue = DispatchQueue(label: "BrainUnfog.ObsidianProjectDirectoryWatcher")

  private var fileDescriptor: CInt = -1
  private var source: DispatchSourceFileSystemObject?
  private var eventStream: FSEventStreamRef?
  private var debounceWorkItem: DispatchWorkItem?
  private var fastDebounceWorkItem: DispatchWorkItem?
  private var pollingTimer: DispatchSourceTimer?
  private var fastPollingTimer: DispatchSourceTimer?
  private var writeObserver: NSObjectProtocol?

  init(
    vaultRootURL: URL,
    debounceNanoseconds: UInt64 = ObsidianProjectDirectoryWatcher.defaultDebounceNanoseconds,
    fastDebounceNanoseconds: UInt64 = ObsidianProjectDirectoryWatcher.defaultFastDebounceNanoseconds,
    pollingNanoseconds: UInt64? = ObsidianProjectDirectoryWatcher.defaultDebounceNanoseconds,
    fastPollingNanoseconds: UInt64? = ObsidianProjectDirectoryWatcher.defaultFastPollingEnabled
      ? ObsidianProjectDirectoryWatcher.defaultFastPollingNanoseconds
      : nil,
    tracker: ObsidianProjectChangeTracker = ObsidianProjectChangeTracker(),
    pollingTracker: ObsidianProjectChangeTracker = ObsidianProjectChangeTracker(),
    fastTracker: ObsidianProjectChangeTracker = ObsidianProjectChangeTracker(),
    fastHandler: FastChangeHandler? = nil,
    handler: @escaping ChangeHandler
  ) {
    self.vaultRootURL = vaultRootURL.standardizedFileURL
    self.projectsRootURL = ObsidianVaultLayout(vaultRootURL: vaultRootURL).rawProjectsRootURL
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
    _ = tracker.changedProjectMarkdownFiles(in: projectsRootURL)
    _ = pollingTracker.changedProjectMarkdownFiles(in: projectsRootURL)
    _ = fastTracker.changedProjectMarkdownFiles(in: projectsRootURL)
    registerWriteObserver()
    startFileEventStream()
    startPollingTimer()
    startFastPollingTimer()

    fileDescriptor = open(projectsRootURL.path, O_EVTONLY)
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
    if let eventStream {
      FSEventStreamStop(eventStream)
      FSEventStreamInvalidate(eventStream)
      FSEventStreamRelease(eventStream)
      self.eventStream = nil
    }
    source?.cancel()
    source = nil
    fileDescriptor = -1
  }

  private func startFileEventStream() {
    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    let paths = [projectsRootURL.path] as CFArray
    let flags = UInt32(
      kFSEventStreamCreateFlagUseCFTypes
        | kFSEventStreamCreateFlagFileEvents
        | kFSEventStreamCreateFlagNoDefer
    )
    guard let stream = FSEventStreamCreate(
      kCFAllocatorDefault,
      Self.fileEventCallback,
      &context,
      paths,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      0.2,
      flags
    ) else {
      return
    }
    FSEventStreamSetDispatchQueue(stream, queue)
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      return
    }
    eventStream = stream
  }

  private static let fileEventCallback: FSEventStreamCallback = {
    _, contextInfo, eventCount, eventPaths, _, _ in
    guard let contextInfo else { return }
    let watcher = Unmanaged<ObsidianProjectDirectoryWatcher>
      .fromOpaque(contextInfo)
      .takeUnretainedValue()
    watcher.handleFileEvents(eventCount: eventCount, eventPaths: eventPaths)
  }

  private func handleFileEvents(eventCount: Int, eventPaths: UnsafeMutableRawPointer) {
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
    guard shouldScanAfterFileEvents(paths, eventCount: eventCount) else { return }
    scheduleFastScan()
    scheduleDebouncedScan()
  }

  private func shouldScanAfterFileEvents(_ paths: [String], eventCount: Int) -> Bool {
    guard eventCount > 0 else { return false }
    guard !paths.isEmpty else { return true }
    let root = projectsRootURL.standardizedFileURL.resolvingSymlinksInPath()
    let rootPath = root.path
    for path in paths {
      let eventURL = URL(fileURLWithPath: path).standardizedFileURL
      if eventURL == root || eventURL.deletingLastPathComponent() == root {
        return true
      }
      if eventURL.path.hasPrefix(rootPath + "/") {
        return true
      }
    }
    return false
  }

  private func startPollingTimer() {
    guard fastHandler == nil, let pollingNanoseconds else { return }
    let interval = DispatchTimeInterval.nanoseconds(Int(min(pollingNanoseconds, UInt64(Int.max))))
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
      forName: .obsidianProjectMarkdownStoreDidWriteMarkdown,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      guard let fileURL = notification.userInfo?[ObsidianProjectMarkdownStoreWriteNotification.fileURLKey] as? URL else {
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
    let delay = DispatchTimeInterval.nanoseconds(Int(min(debounceNanoseconds, UInt64(Int.max))))
    let workItem = DispatchWorkItem { [weak self] in
      self?.runScan()
    }
    debounceWorkItem = workItem
    queue.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func runFastScan() {
    guard let fastHandler else { return }
    let changedFiles = fastTracker.changedProjectMarkdownFiles(in: projectsRootURL)
    guard !changedFiles.isEmpty else { return }
    scheduleDebouncedScan()
    Task { @MainActor in
      fastHandler()
    }
  }

  private func scheduleDebouncedScanIfPollingChanged() {
    let changedFiles = pollingTracker.changedProjectMarkdownFiles(in: projectsRootURL)
    guard !changedFiles.isEmpty else { return }
    scheduleDebouncedScan()
  }

  private func runScan() {
    let changedFiles = tracker.changedProjectMarkdownFiles(in: projectsRootURL)
    guard !changedFiles.isEmpty else { return }
    Task { @MainActor [handler] in
      await handler(changedFiles)
    }
  }
}
