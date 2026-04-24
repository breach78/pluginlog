import Foundation
import SQLite3
import UniformTypeIdentifiers
import CryptoKit
#if canImport(AppKit)
import AppKit
#endif

private enum PlatformBookmarkOptions {
  static var creation: URL.BookmarkCreationOptions {
    #if canImport(UIKit) && !canImport(AppKit)
      return []
    #else
      return [.withSecurityScope]
    #endif
  }

  static var resolution: URL.BookmarkResolutionOptions {
    #if canImport(UIKit) && !canImport(AppKit)
      return []
    #else
      return [.withSecurityScope]
    #endif
  }
}

struct ImportedDocumentReference: Equatable {
  var record: AttachmentReferenceRecord
  var sourceURL: URL
}

struct DocumentReferenceChangeEvent: Equatable, Sendable {
  enum Kind: String, Equatable, Sendable {
    case modified
    case moved
    case deleted
  }

  var referenceID: UUID
  var kind: Kind
  var url: URL?
}

enum DocumentReferenceError: LocalizedError {
  case invalidOwner
  case inPlaceAccessUnavailable
  case missingBookmark
  case securityScopeUnavailable
  case externalOpenFailed
  case referenceNotFound

  var errorDescription: String? {
    switch self {
    case .invalidOwner:
      return "첨부 owner 정보가 유효하지 않습니다."
    case .inPlaceAccessUnavailable:
      return "원본 문서를 open-in-place로 열 수 없습니다."
    case .missingBookmark:
      return "문서 bookmark 데이터가 없습니다."
    case .securityScopeUnavailable:
      return "문서 보안 범위를 확보하지 못했습니다."
    case .externalOpenFailed:
      return "외부 앱으로 문서를 열지 못했습니다."
    case .referenceNotFound:
      return "문서 참조를 찾지 못했습니다."
    }
  }
}

/// Retained runtime sqlite sidecar repository for attachment references.
actor NormalizedDocumentReferenceRepository {
  private let databaseURL: URL
  private let fileManager: FileManager

  init(databaseURL: URL, fileManager: FileManager = .default) {
    self.databaseURL = databaseURL
    self.fileManager = fileManager
  }

  func upsert(_ record: AttachmentReferenceRecord) throws {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try installAttachmentSchemaIfNeeded(in: db)

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      INSERT INTO attachment_references(
        id, owner_type_raw, owner_id, storage_kind, relative_path, bookmark_data, original_filename,
        mime_type, byte_size, sha256, is_archived, created_at, updated_at
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
      ON CONFLICT(id) DO UPDATE SET
        owner_type_raw = excluded.owner_type_raw,
        owner_id = excluded.owner_id,
        storage_kind = excluded.storage_kind,
        relative_path = excluded.relative_path,
        bookmark_data = excluded.bookmark_data,
        original_filename = excluded.original_filename,
        mime_type = excluded.mime_type,
        byte_size = excluded.byte_size,
        sha256 = excluded.sha256,
        is_archived = excluded.is_archived,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at;
      """,
      in: db,
      statement: &statement
    )

    try bind(record.id.uuidString, at: 1, to: statement)
    try bind(record.ownerTypeRaw, at: 2, to: statement)
    try bind(record.ownerID.uuidString, at: 3, to: statement)
    try bind(record.storageKind.rawValue, at: 4, to: statement)
    try bind(record.relativePath, at: 5, to: statement)
    try bind(record.bookmarkData, at: 6, to: statement)
    try bind(record.originalFilename, at: 7, to: statement)
    try bind(record.mimeType, at: 8, to: statement)
    try bind(record.byteSize, at: 9, to: statement)
    try bind(record.sha256, at: 10, to: statement)
    try bind(record.isArchived, at: 11, to: statement)
    try bind(record.createdAt, at: 12, to: statement)
    try bind(record.updatedAt, at: 13, to: statement)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(db))
    }
  }

  func record(for id: UUID) throws -> AttachmentReferenceRecord? {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try installAttachmentSchemaIfNeeded(in: db)

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT id, owner_type_raw, owner_id, storage_kind, relative_path, bookmark_data,
             original_filename, mime_type, byte_size, sha256, is_archived, created_at, updated_at
      FROM attachment_references
      WHERE id = ?1;
      """,
      in: db,
      statement: &statement
    )
    try bind(id.uuidString, at: 1, to: statement)

    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return try decodeRecord(from: statement)
  }

  func references(ownerType: AttachmentOwnerType, ownerID: UUID) throws -> [AttachmentReferenceRecord] {
    let db = try openDatabase()
    defer { sqlite3_close(db) }
    try installAttachmentSchemaIfNeeded(in: db)

    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try prepare(
      """
      SELECT id, owner_type_raw, owner_id, storage_kind, relative_path, bookmark_data,
             original_filename, mime_type, byte_size, sha256, is_archived, created_at, updated_at
      FROM attachment_references
      WHERE owner_type_raw = ?1 AND owner_id = ?2
      ORDER BY updated_at DESC, created_at DESC;
      """,
      in: db,
      statement: &statement
    )
    try bind(ownerType.rawValue, at: 1, to: statement)
    try bind(ownerID.uuidString, at: 2, to: statement)

    var results: [AttachmentReferenceRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      results.append(try decodeRecord(from: statement))
    }
    return results
  }

  private func decodeRecord(from statement: OpaquePointer?) throws -> AttachmentReferenceRecord {
    guard
      let idString = Self.columnText(statement, index: 0),
      let id = UUID(uuidString: idString),
      let ownerTypeRaw = Self.columnText(statement, index: 1),
      let ownerIDString = Self.columnText(statement, index: 2),
      let ownerID = UUID(uuidString: ownerIDString),
      let storageKindRaw = Self.columnText(statement, index: 3),
      let storageKind = AttachmentReferenceStorageKind(rawValue: storageKindRaw),
      let originalFilename = Self.columnText(statement, index: 6),
      let mimeType = Self.columnText(statement, index: 7),
      let sha256 = Self.columnText(statement, index: 9)
    else {
      throw NormalizedPersistenceError.metadataDecodeFailed
    }

    return AttachmentReferenceRecord(
      id: id,
      ownerTypeRaw: ownerTypeRaw,
      ownerID: ownerID,
      storageKind: storageKind,
      relativePath: Self.columnText(statement, index: 4),
      bookmarkData: Self.columnBlob(statement, index: 5),
      originalFilename: originalFilename,
      mimeType: mimeType,
      byteSize: sqlite3_column_int64(statement, 8),
      sha256: sha256,
      isArchived: sqlite3_column_int(statement, 10) != 0,
      createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
      updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 12))
    )
  }

  private func openDatabase() throws -> OpaquePointer? {
    try openNormalizedSQLiteConnection(
      at: databaseURL,
      fileManager: fileManager
    )
  }

  private func installAttachmentSchemaIfNeeded(in db: OpaquePointer?) throws {
    try execute(
      """
      CREATE TABLE IF NOT EXISTS attachment_references (
        id TEXT PRIMARY KEY,
        owner_type_raw TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        storage_kind TEXT NOT NULL,
        relative_path TEXT,
        bookmark_data BLOB,
        original_filename TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        byte_size INTEGER NOT NULL,
        sha256 TEXT NOT NULL,
        is_archived INTEGER NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
      );
      """,
      in: db
    )
    try execute(
      "CREATE INDEX IF NOT EXISTS idx_attachment_refs_owner ON attachment_references(owner_type_raw, owner_id);",
      in: db
    )
  }

  private func execute(_ sql: String, in db: OpaquePointer?) throws {
    var errorPointer: UnsafeMutablePointer<Int8>?
    guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
      let message = errorPointer.map { String(cString: $0) } ?? Self.sqliteMessage(db)
      sqlite3_free(errorPointer)
      throw NormalizedPersistenceError.sqliteExecFailed(message)
    }
  }

  private func prepare(_ sql: String, in db: OpaquePointer?, statement: inout OpaquePointer?) throws {
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqlitePrepareFailed(Self.sqliteMessage(db))
    }
  }

  private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer?) throws {
    let result: Int32
    if let value {
      result = sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransientDestructor)
    } else {
      result = sqlite3_bind_null(statement, index)
    }
    guard result == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
    }
  }

  private func bind(_ value: Int64, at index: Int32, to statement: OpaquePointer?) throws {
    guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
    }
  }

  private func bind(_ value: Bool, at index: Int32, to statement: OpaquePointer?) throws {
    guard sqlite3_bind_int(statement, index, value ? 1 : 0) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
    }
  }

  private func bind(_ value: Date, at index: Int32, to statement: OpaquePointer?) throws {
    guard sqlite3_bind_double(statement, index, value.timeIntervalSince1970) == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
    }
  }

  private func bind(_ value: Data?, at index: Int32, to statement: OpaquePointer?) throws {
    let result: Int32
    if let value {
      result = value.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), Self.sqliteTransientDestructor)
      }
    } else {
      result = sqlite3_bind_null(statement, index)
    }
    guard result == SQLITE_OK else {
      throw NormalizedPersistenceError.sqliteStepFailed(Self.sqliteMessage(sqlite3_db_handle(statement)))
    }
  }

  private static func sqliteMessage(_ db: OpaquePointer?) -> String {
    guard let db, let message = sqlite3_errmsg(db) else { return "unknown" }
    return String(cString: message)
  }

  private static func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: value)
  }

  private static func columnBlob(_ statement: OpaquePointer?, index: Int32) -> Data? {
    guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
    let count = Int(sqlite3_column_bytes(statement, index))
    return Data(bytes: bytes, count: count)
  }

  private static let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

final class SecurityScopedDocumentReferenceImporter: @unchecked Sendable {
  private let repository: NormalizedDocumentReferenceRepository
  private let fileCoordinator = NSFileCoordinator()

  init(repository: NormalizedDocumentReferenceRepository) {
    self.repository = repository
  }

  func importPickedURL(
    _ url: URL,
    ownerType: AttachmentOwnerType,
    ownerID: UUID
  ) async throws -> ImportedDocumentReference {
    let coordinatedURL = try Self.coordinateReading(url)
    let bookmarkData = try coordinatedURL.bookmarkData(
      options: PlatformBookmarkOptions.creation,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    let values = try coordinatedURL.resourceValues(forKeys: [
      .fileSizeKey,
      .contentTypeKey,
      .nameKey,
    ])
    let contentType = values.contentType ?? UTType(filenameExtension: coordinatedURL.pathExtension) ?? .data
    let filename = values.name ?? coordinatedURL.lastPathComponent
    let now = Date()
    let record = AttachmentReferenceRecord(
      id: UUID(),
      ownerTypeRaw: ownerType.rawValue,
      ownerID: ownerID,
      storageKind: .securityScopedBookmark,
      relativePath: nil,
      bookmarkData: bookmarkData,
      originalFilename: filename,
      mimeType: contentType.preferredMIMEType ?? "application/octet-stream",
      byteSize: Int64(values.fileSize ?? 0),
      sha256: Self.sha256Hex(for: bookmarkData),
      isArchived: false,
      createdAt: now,
      updatedAt: now
    )
    try await repository.upsert(record)
    return ImportedDocumentReference(record: record, sourceURL: coordinatedURL)
  }

  func importItemProvider(
    _ provider: NSItemProvider,
    ownerType: AttachmentOwnerType,
    ownerID: UUID
  ) async throws -> ImportedDocumentReference {
    let inPlaceURL = try await loadInPlaceURL(from: provider)
    return try await importPickedURL(inPlaceURL, ownerType: ownerType, ownerID: ownerID)
  }

  func importItemProviders(
    _ providers: [NSItemProvider],
    ownerType: AttachmentOwnerType,
    ownerID: UUID
  ) async throws -> [ImportedDocumentReference] {
    var imported: [ImportedDocumentReference] = []
    for provider in providers {
      imported.append(try await importItemProvider(provider, ownerType: ownerType, ownerID: ownerID))
    }
    return imported
  }

  private func loadInPlaceURL(from provider: NSItemProvider) async throws -> URL {
    let typeIdentifier = provider.registeredContentTypesForOpenInPlace.first?.identifier
      ?? provider.registeredTypeIdentifiers.first
      ?? UTType.data.identifier

    return try await withCheckedThrowingContinuation { continuation in
      _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, isInPlace, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let url else {
          continuation.resume(throwing: DocumentReferenceError.inPlaceAccessUnavailable)
          return
        }
        guard isInPlace else {
          continuation.resume(throwing: DocumentReferenceError.inPlaceAccessUnavailable)
          return
        }
        do {
          let coordinatedURL = try Self.coordinateReading(url)
          continuation.resume(returning: coordinatedURL)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func coordinateReading(_ url: URL) throws -> URL {
    var resolvedURL: URL?
    var coordinationError: NSError?
    let coordinator = NSFileCoordinator()
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
      resolvedURL = $0
    }
    if let coordinationError {
      throw coordinationError
    }
    return resolvedURL ?? url
  }

  static func sha256Hex(for data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

final class SecurityScopedDocumentReferenceSession: @unchecked Sendable {
  let record: AttachmentReferenceRecord
  let url: URL

  private let stopAccessingOnClose: Bool
  private let fileCoordinator = NSFileCoordinator()
  private var hasClosed = false

  init(record: AttachmentReferenceRecord, url: URL, stopAccessingOnClose: Bool) {
    self.record = record
    self.url = url
    self.stopAccessingOnClose = stopAccessingOnClose
  }

  deinit {
    close()
  }

  func coordinatedRead<T>(_ body: (URL) throws -> T) throws -> T {
    var result: Result<T, Error>?
    var coordinationError: NSError?
    fileCoordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
      result = Result { try body(coordinatedURL) }
    }
    if let coordinationError {
      throw coordinationError
    }
    return try result?.get() ?? body(url)
  }

  func close() {
    guard !hasClosed else { return }
    hasClosed = true
    if stopAccessingOnClose {
      url.stopAccessingSecurityScopedResource()
    }
  }
}

final class SecurityScopedDocumentReferenceAccessService: @unchecked Sendable {
  private let repository: NormalizedDocumentReferenceRepository

  init(repository: NormalizedDocumentReferenceRepository) {
    self.repository = repository
  }

  func openSession(for referenceID: UUID) async throws -> SecurityScopedDocumentReferenceSession {
    guard let record = try await repository.record(for: referenceID) else {
      throw DocumentReferenceError.referenceNotFound
    }
    return try await openSession(for: record)
  }

  func openSession(for record: AttachmentReferenceRecord) async throws -> SecurityScopedDocumentReferenceSession {
    guard let bookmarkData = record.bookmarkData else {
      throw DocumentReferenceError.missingBookmark
    }

    var isStale = false
    let resolvedURL = try URL(
      resolvingBookmarkData: bookmarkData,
      options: PlatformBookmarkOptions.resolution,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    if isStale {
      let refreshedBookmark = try resolvedURL.bookmarkData(
        options: PlatformBookmarkOptions.creation,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      var updatedRecord = record
      updatedRecord.bookmarkData = refreshedBookmark
      updatedRecord.updatedAt = .now
      updatedRecord.sha256 = SecurityScopedDocumentReferenceImporter.sha256Hex(for: refreshedBookmark)
      try await repository.upsert(updatedRecord)
      return try await openSession(for: updatedRecord)
    }

    let didStartSecurityScope = resolvedURL.startAccessingSecurityScopedResource()
    guard didStartSecurityScope else {
      throw DocumentReferenceError.securityScopeUnavailable
    }

    return SecurityScopedDocumentReferenceSession(
      record: record,
      url: resolvedURL,
      stopAccessingOnClose: didStartSecurityScope
    )
  }
}

final class DocumentReferencePresenterPool {
  let changes: AsyncStream<DocumentReferenceChangeEvent>

  private let continuation: AsyncStream<DocumentReferenceChangeEvent>.Continuation
  private var presenters: [UUID: DocumentReferenceFilePresenter] = [:]

  init() {
    var capturedContinuation: AsyncStream<DocumentReferenceChangeEvent>.Continuation?
    let changes = AsyncStream<DocumentReferenceChangeEvent> { continuation in
      capturedContinuation = continuation
    }
    guard let capturedContinuation else {
      preconditionFailure("AsyncStream continuation was not initialized")
    }
    self.changes = changes
    self.continuation = capturedContinuation
  }

  deinit {
    presenters.values.forEach(NSFileCoordinator.removeFilePresenter)
    continuation.finish()
  }

  func beginObserving(referenceID: UUID, session: SecurityScopedDocumentReferenceSession) {
    stopObserving(referenceID: referenceID)
    let presenter = DocumentReferenceFilePresenter(referenceID: referenceID, url: session.url) { [weak self] event in
      self?.continuation.yield(event)
    }
    presenters[referenceID] = presenter
    NSFileCoordinator.addFilePresenter(presenter)
  }

  func stopObserving(referenceID: UUID) {
    guard let presenter = presenters.removeValue(forKey: referenceID) else { return }
    NSFileCoordinator.removeFilePresenter(presenter)
  }
}

private final class DocumentReferenceFilePresenter: NSObject, NSFilePresenter {
  private let referenceID: UUID
  private let eventHandler: (DocumentReferenceChangeEvent) -> Void

  var presentedItemURL: URL?
  let presentedItemOperationQueue: OperationQueue

  init(referenceID: UUID, url: URL, eventHandler: @escaping (DocumentReferenceChangeEvent) -> Void) {
    self.referenceID = referenceID
    self.presentedItemURL = url
    self.eventHandler = eventHandler
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    self.presentedItemOperationQueue = queue
    super.init()
  }

  func presentedItemDidChange() {
    eventHandler(
      DocumentReferenceChangeEvent(referenceID: referenceID, kind: .modified, url: presentedItemURL)
    )
  }

  func presentedItemDidMove(to newURL: URL) {
    presentedItemURL = newURL
    eventHandler(
      DocumentReferenceChangeEvent(referenceID: referenceID, kind: .moved, url: newURL)
    )
  }

  func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
    eventHandler(
      DocumentReferenceChangeEvent(referenceID: referenceID, kind: .deleted, url: presentedItemURL)
    )
    completionHandler(nil)
  }
}

@MainActor
final class DocumentReferenceExternalOpenCoordinator {
  private let documentOpener: any PlatformDocumentOpening

  init(documentOpener: any PlatformDocumentOpening = ApplePlatformDocumentOpener.shared) {
    self.documentOpener = documentOpener
  }

  func open(_ session: SecurityScopedDocumentReferenceSession) throws {
    do {
      try documentOpener.open(session.url)
    } catch {
      throw DocumentReferenceError.externalOpenFailed
    }
  }
}

struct DocumentReferenceDropLoader {
  let importer: SecurityScopedDocumentReferenceImporter

  func importProviders(
    _ providers: [NSItemProvider],
    ownerType: AttachmentOwnerType,
    ownerID: UUID
  ) async throws -> [ImportedDocumentReference] {
    try await importer.importItemProviders(providers, ownerType: ownerType, ownerID: ownerID)
  }
}
