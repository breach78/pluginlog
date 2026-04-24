import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

enum AttachmentOwner: Sendable, Hashable {
    case project(UUID)
    case task(UUID)

    var ownerType: AttachmentOwnerType {
        switch self {
        case .project: .project
        case .task: .task
        }
    }

    var ownerID: UUID {
        switch self {
        case .project(let id): id
        case .task(let id): id
        }
    }
}

struct DeletedAttachmentSnapshot: Sendable {
    let id: UUID
    let ownerTypeRaw: String
    let ownerID: UUID
    let relativePath: String
    let originalFilename: String
    let mimeType: String
    let byteSize: Int64
    let sha256: String
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    var trashedFileURL: URL?
}

struct ProjectTaskAttachmentIndexEntry: Codable, Hashable, Identifiable {
    let attachmentID: UUID
    let taskID: UUID
    let relativePath: String
    let originalFilename: String
    let byteSize: Int64
    let updatedAt: Date

    var id: UUID { attachmentID }
}

struct ProjectTaskAttachmentIndexSnapshot: Codable {
    let projectID: UUID
    var updatedAt: Date
    var entries: [ProjectTaskAttachmentIndexEntry]
}

enum ProjectTaskAttachmentIndexStore {
    private static let directoryName = "project-task-attachment-index"

    static func read(
        projectID: UUID,
        paths: ContainerPaths,
        fileManager: FileManager = .default
    ) -> ProjectTaskAttachmentIndexSnapshot? {
        let url = indexURL(for: projectID, paths: paths)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ProjectTaskAttachmentIndexSnapshot.self, from: data)
        } catch {
            AppLogger.attachment.error(
                "read project task attachment index failed. project=\(projectID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func write(
        _ snapshot: ProjectTaskAttachmentIndexSnapshot,
        paths: ContainerPaths,
        fileManager: FileManager = .default
    ) throws {
        let directory = indexDirectory(paths: paths)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: indexURL(for: snapshot.projectID, paths: paths), options: .atomic)
    }

    static func upsert(
        attachment: AttachmentEntity,
        taskID: UUID,
        projectID: UUID,
        paths: ContainerPaths,
        fileManager: FileManager = .default
    ) throws {
        var snapshot = read(projectID: projectID, paths: paths, fileManager: fileManager)
            ?? ProjectTaskAttachmentIndexSnapshot(projectID: projectID, updatedAt: .now, entries: [])

        let entry = ProjectTaskAttachmentIndexEntry(
            attachmentID: attachment.id,
            taskID: taskID,
            relativePath: attachment.relativePath,
            originalFilename: attachment.originalFilename,
            byteSize: attachment.byteSize,
            updatedAt: attachment.updatedAt
        )

        snapshot.entries.removeAll { $0.attachmentID == attachment.id }
        snapshot.entries.append(entry)
        snapshot.updatedAt = .now
        try write(snapshot, paths: paths, fileManager: fileManager)
    }

    static func remove(
        attachmentID: UUID,
        projectID: UUID,
        paths: ContainerPaths,
        fileManager: FileManager = .default
    ) throws {
        guard var snapshot = read(projectID: projectID, paths: paths, fileManager: fileManager) else {
            return
        }

        snapshot.entries.removeAll { $0.attachmentID == attachmentID }
        snapshot.updatedAt = .now
        try write(snapshot, paths: paths, fileManager: fileManager)
    }

    static func rebuild(
        projectID: UUID,
        entries: [ProjectTaskAttachmentIndexEntry],
        paths: ContainerPaths,
        fileManager: FileManager = .default
    ) throws {
        let snapshot = ProjectTaskAttachmentIndexSnapshot(
            projectID: projectID,
            updatedAt: .now,
            entries: entries
        )
        try write(snapshot, paths: paths, fileManager: fileManager)
    }

    static func projectIDs(
        containingTaskID taskID: UUID,
        paths: ContainerPaths,
        fileManager: FileManager = .default
    ) -> [UUID] {
        let directory = indexDirectory(paths: paths)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var projectIDs: [UUID] = []
        for url in urls where url.pathExtension == "json" {
            guard let projectID = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let snapshot = read(
                      projectID: projectID,
                      paths: paths,
                      fileManager: fileManager
                  ),
                  snapshot.entries.contains(where: { $0.taskID == taskID }) else {
                continue
            }
            projectIDs.append(projectID)
        }
        return projectIDs
    }

    private static func indexDirectory(paths: ContainerPaths) -> URL {
        paths.cacheDirectory.appendingPathComponent(directoryName, conformingTo: .directory)
    }

    private static func indexURL(for projectID: UUID, paths: ContainerPaths) -> URL {
        indexDirectory(paths: paths)
            .appendingPathComponent(projectID.uuidString)
            .appendingPathExtension("json")
    }
}

@MainActor
protocol AttachmentStore: AnyObject {
    func `import`(from sourceURL: URL, owner: AttachmentOwner, in context: ModelContext) throws -> AttachmentEntity
    func move(_ attachment: AttachmentEntity, to owner: AttachmentOwner, in context: ModelContext) throws
    func moveToArchive(_ attachment: AttachmentEntity, in context: ModelContext) throws
    func restoreFromArchive(_ attachment: AttachmentEntity, in context: ModelContext) throws
    func resolve(_ attachment: AttachmentEntity) throws -> URL
    func deletePermanent(_ attachment: AttachmentEntity, in context: ModelContext) throws
    func deleteWithUndoSnapshot(_ attachment: AttachmentEntity, in context: ModelContext) throws -> DeletedAttachmentSnapshot
    func restoreDeletedAttachment(_ snapshot: DeletedAttachmentSnapshot, in context: ModelContext) throws -> AttachmentEntity
}

enum AttachmentStoreError: LocalizedError {
    case containerUnavailable
    case cannotResolvePath
    case cannotRestoreFromTrash
    case integrityCheckFailed

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            "컨테이너가 열려 있지 않습니다."
        case .cannotResolvePath:
            "첨부 파일 경로를 해석할 수 없습니다."
        case .cannotRestoreFromTrash:
            "휴지통에서 첨부 파일을 복구할 수 없습니다."
        case .integrityCheckFailed:
            "첨부 파일 무결성 검증에 실패했습니다."
        }
    }
}

@MainActor
final class LocalAttachmentStore: AttachmentStore {
    private struct TaskMutationSnapshot {
        let taskContent: TaskContent?
        let taskItem: TaskItem?
        let taskContentAttachmentCount: Int?
        let taskContentLocalUpdatedAt: Date?
        let taskContentWasDirty: Bool?
        let taskItemAttachmentCount: Int?
        let taskItemLocalUpdatedAt: Date?
        let taskItemWasDirty: Bool?
    }

    private struct ProjectMutationSnapshot {
        let projects: [(project: ProjectRecord, updatedAt: Date)]
    }

    private let storage: LocalStorageCoordinator
    private let fileManager: FileManager
    private let runtimeSnapshotProvider: () -> OutlineProjectionRuntimeSnapshot?

    init(
        storage: LocalStorageCoordinator,
        fileManager: FileManager = .default,
        runtimeSnapshotProvider: @escaping () -> OutlineProjectionRuntimeSnapshot? = { nil }
    ) {
        self.storage = storage
        self.fileManager = fileManager
        self.runtimeSnapshotProvider = runtimeSnapshotProvider
    }

    func `import`(from sourceURL: URL, owner: AttachmentOwner, in context: ModelContext) throws -> AttachmentEntity {
        guard let paths = storage.paths else {
            AppLogger.attachment.error("import attachment failed because container is unavailable")
            throw AttachmentStoreError.containerUnavailable
        }

        let ownerDirectory: URL
        switch owner.ownerType {
        case .project:
            ownerDirectory = paths.projectAttachmentsDirectory.appendingPathComponent(owner.ownerID.uuidString, conformingTo: .directory)
        case .task:
            ownerDirectory = paths.taskAttachmentsDirectory.appendingPathComponent(owner.ownerID.uuidString, conformingTo: .directory)
        }

        try fileManager.createDirectory(at: ownerDirectory, withIntermediateDirectories: true)

        let preferredFilename = sourceURL.lastPathComponent.isEmpty ? "Attachment" : sourceURL.lastPathComponent
        let destination = uniqueDestinationURL(in: ownerDirectory, preferredFilename: preferredFilename)
        let storedFilename = destination.lastPathComponent
        try fileManager.copyItem(at: sourceURL, to: destination)

        let values = try destination.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let size = Int64(values.fileSize ?? 0)
        let mime = values.contentType?.preferredMIMEType ?? "application/octet-stream"
        let sha256 = try Self.sha256(of: destination)

        let relativePath = Self.relativePath(from: paths.root, to: destination)
        let now = Date()

        let attachment = AttachmentEntity(
            ownerType: owner.ownerType,
            ownerID: owner.ownerID,
            relativePath: relativePath,
            originalFilename: storedFilename,
            mimeType: mime,
            byteSize: size,
            sha256: sha256,
            createdAt: now,
            updatedAt: now
        )
        context.insert(attachment)

        let taskSnapshot = try applyTaskAttachmentDelta(
            ownerType: owner.ownerType,
            ownerID: owner.ownerID,
            occurredAt: now,
            delta: 1,
            in: context
        )
        let projectSnapshot = try touchProjectIfNeeded(
            ownerType: owner.ownerType,
            ownerID: owner.ownerID,
            occurredAt: now,
            in: context
        )

        do {
            try context.save()
            updateTaskAttachmentIndexIfNeeded(
                action: .upsert(attachment),
                ownerType: owner.ownerType,
                ownerID: owner.ownerID,
                in: context
            )
            return attachment
        } catch {
            context.delete(attachment)
            restoreTaskMutation(taskSnapshot)
            restoreProjectMutation(projectSnapshot)
            try? fileManager.removeItem(at: destination)
            AppLogger.attachment.error(
                "import attachment failed. source=\(sourceURL.path, privacy: .public) owner=\(owner.ownerID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    func move(_ attachment: AttachmentEntity, to owner: AttachmentOwner, in context: ModelContext) throws {
        guard let paths = storage.paths else {
            AppLogger.attachment.error("move attachment failed because container is unavailable")
            throw AttachmentStoreError.containerUnavailable
        }

        let resolvedCurrentOwner: AttachmentOwner = attachment.ownerType == .project
            ? .project(attachment.ownerID)
            : .task(attachment.ownerID)
        guard resolvedCurrentOwner != owner else { return }

        let source = try resolve(attachment)
        let destinationDirectory: URL
        switch owner.ownerType {
        case .project:
            destinationDirectory = paths.projectAttachmentsDirectory
                .appendingPathComponent(owner.ownerID.uuidString, conformingTo: .directory)
        case .task:
            destinationDirectory = paths.taskAttachmentsDirectory
                .appendingPathComponent(owner.ownerID.uuidString, conformingTo: .directory)
        }

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = uniqueDestinationURL(
            in: destinationDirectory,
            preferredFilename: attachment.originalFilename
        )

        let originalOwnerType = attachment.ownerType
        let originalOwnerID = attachment.ownerID
        let originalRelativePath = attachment.relativePath
        let originalFilename = attachment.originalFilename
        let originalUpdatedAt = attachment.updatedAt
        let now = Date()

        if fileManager.fileExists(atPath: source.path) {
            try fileManager.moveItem(at: source, to: destination)
        }

        let oldTaskSnapshot = try applyTaskAttachmentDelta(
            ownerType: originalOwnerType,
            ownerID: originalOwnerID,
            occurredAt: now,
            delta: -1,
            in: context
        )
        let oldProjectSnapshot = try touchProjectIfNeeded(
            ownerType: originalOwnerType,
            ownerID: originalOwnerID,
            occurredAt: now,
            in: context
        )

        attachment.ownerType = owner.ownerType
        attachment.ownerID = owner.ownerID
        attachment.relativePath = Self.relativePath(from: paths.root, to: destination)
        attachment.originalFilename = destination.lastPathComponent
        attachment.updatedAt = now

        let newTaskSnapshot = try applyTaskAttachmentDelta(
            ownerType: attachment.ownerType,
            ownerID: attachment.ownerID,
            occurredAt: now,
            delta: 1,
            in: context
        )
        let newProjectSnapshot = try touchProjectIfNeeded(
            ownerType: attachment.ownerType,
            ownerID: attachment.ownerID,
            occurredAt: now,
            in: context
        )

        do {
            try context.save()
            updateTaskAttachmentIndexIfNeeded(
                action: .remove(attachment.id),
                ownerType: originalOwnerType,
                ownerID: originalOwnerID,
                in: context
            )
            updateTaskAttachmentIndexIfNeeded(
                action: .upsert(attachment),
                ownerType: attachment.ownerType,
                ownerID: attachment.ownerID,
                in: context
            )
        } catch {
            attachment.ownerType = originalOwnerType
            attachment.ownerID = originalOwnerID
            attachment.relativePath = originalRelativePath
            attachment.originalFilename = originalFilename
            attachment.updatedAt = originalUpdatedAt
            restoreTaskMutation(oldTaskSnapshot)
            restoreProjectMutation(oldProjectSnapshot)
            restoreTaskMutation(newTaskSnapshot)
            restoreProjectMutation(newProjectSnapshot)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: destination, to: source)
            }
            AppLogger.attachment.error(
                "move attachment failed. attachment=\(attachment.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    func moveToArchive(_ attachment: AttachmentEntity, in context: ModelContext) throws {
        guard let paths = storage.paths else {
            AppLogger.attachment.error("archive attachment failed because container is unavailable")
            throw AttachmentStoreError.containerUnavailable
        }

        let source = try resolve(attachment)
        let destinationDirectory = paths.archiveAttachmentsDirectory
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let destination = destinationDirectory.appendingPathComponent("\(attachment.id.uuidString)-\(source.lastPathComponent)")

        if fileManager.fileExists(atPath: destination.path) {
            _ = try moveItemToTrash(destination)
        }

        let originalRelativePath = attachment.relativePath
        let originalArchivedState = attachment.isArchived
        let originalUpdatedAt = attachment.updatedAt
        let now = Date()

        if fileManager.fileExists(atPath: source.path) {
            try fileManager.moveItem(at: source, to: destination)
        }

        attachment.relativePath = Self.relativePath(from: paths.root, to: destination)
        attachment.isArchived = true
        attachment.updatedAt = now
        let taskSnapshot = try applyTaskAttachmentDelta(
            ownerType: attachment.ownerType,
            ownerID: attachment.ownerID,
            occurredAt: now,
            delta: -1,
            in: context
        )
        let projectSnapshot = try touchProjectIfNeeded(
            ownerType: attachment.ownerType,
            ownerID: attachment.ownerID,
            occurredAt: now,
            in: context
        )

        do {
            try context.save()
            updateTaskAttachmentIndexIfNeeded(
                action: .remove(attachment.id),
                ownerType: attachment.ownerType,
                ownerID: attachment.ownerID,
                in: context
            )
        } catch {
            attachment.relativePath = originalRelativePath
            attachment.isArchived = originalArchivedState
            attachment.updatedAt = originalUpdatedAt
            restoreTaskMutation(taskSnapshot)
            restoreProjectMutation(projectSnapshot)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: destination, to: source)
            }
            AppLogger.attachment.error(
                "archive attachment failed. attachment=\(attachment.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    func restoreFromArchive(_ attachment: AttachmentEntity, in context: ModelContext) throws {
        guard let paths = storage.paths else {
            AppLogger.attachment.error("restore attachment failed because container is unavailable")
            throw AttachmentStoreError.containerUnavailable
        }

        let source = try resolve(attachment)
        let ownerDirectory: URL
        switch attachment.ownerType {
        case .project:
            ownerDirectory = paths.projectAttachmentsDirectory
                .appendingPathComponent(attachment.ownerID.uuidString, conformingTo: .directory)
        case .task:
            ownerDirectory = paths.taskAttachmentsDirectory
                .appendingPathComponent(attachment.ownerID.uuidString, conformingTo: .directory)
        }

        try fileManager.createDirectory(at: ownerDirectory, withIntermediateDirectories: true)

        let destination = uniqueDestinationURL(in: ownerDirectory, preferredFilename: attachment.originalFilename)
        if fileManager.fileExists(atPath: source.path) {
            try fileManager.moveItem(at: source, to: destination)
        }

        let originalRelativePath = attachment.relativePath
        let originalFilename = attachment.originalFilename
        let originalArchivedState = attachment.isArchived
        let originalUpdatedAt = attachment.updatedAt
        let now = Date()

        attachment.relativePath = Self.relativePath(from: paths.root, to: destination)
        attachment.originalFilename = destination.lastPathComponent
        attachment.isArchived = false
        attachment.updatedAt = now

        let taskSnapshot = try applyTaskAttachmentDelta(
            ownerType: attachment.ownerType,
            ownerID: attachment.ownerID,
            occurredAt: now,
            delta: 1,
            in: context
        )
        let projectSnapshot = try touchProjectIfNeeded(
            ownerType: attachment.ownerType,
            ownerID: attachment.ownerID,
            occurredAt: now,
            in: context
        )

        do {
            try context.save()
            updateTaskAttachmentIndexIfNeeded(
                action: .upsert(attachment),
                ownerType: attachment.ownerType,
                ownerID: attachment.ownerID,
                in: context
            )
        } catch {
            attachment.relativePath = originalRelativePath
            attachment.originalFilename = originalFilename
            attachment.isArchived = originalArchivedState
            attachment.updatedAt = originalUpdatedAt
            restoreTaskMutation(taskSnapshot)
            restoreProjectMutation(projectSnapshot)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: destination, to: source)
            }
            AppLogger.attachment.error(
                "restore attachment failed. attachment=\(attachment.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    func resolve(_ attachment: AttachmentEntity) throws -> URL {
        guard let paths = storage.paths else {
            AppLogger.attachment.error("resolve attachment failed because container is unavailable")
            throw AttachmentStoreError.containerUnavailable
        }

        let absolute = paths.root.appendingPathComponent(attachment.relativePath)
        if fileManager.fileExists(atPath: absolute.path) {
            return absolute
        }

        AppLogger.attachment.error(
            "resolve attachment failed because file is missing. attachment=\(attachment.id.uuidString, privacy: .public) path=\(absolute.path, privacy: .public)"
        )
        throw AttachmentStoreError.cannotResolvePath
    }

    func deletePermanent(_ attachment: AttachmentEntity, in context: ModelContext) throws {
        _ = try delete(attachment, in: context, captureUndoSnapshot: false)
    }

    func deleteWithUndoSnapshot(_ attachment: AttachmentEntity, in context: ModelContext) throws -> DeletedAttachmentSnapshot {
        guard let snapshot = try delete(attachment, in: context, captureUndoSnapshot: true) else {
            throw AttachmentStoreError.cannotRestoreFromTrash
        }
        return snapshot
    }

    func restoreDeletedAttachment(_ snapshot: DeletedAttachmentSnapshot, in context: ModelContext) throws -> AttachmentEntity {
        guard let paths = storage.paths else {
            AppLogger.attachment.error("restore deleted attachment failed because container is unavailable")
            throw AttachmentStoreError.containerUnavailable
        }

        guard let trashedURL = snapshot.trashedFileURL,
              fileManager.fileExists(atPath: trashedURL.path) else {
            AppLogger.attachment.error(
                "restore deleted attachment failed because trashed file is missing. attachment=\(snapshot.id.uuidString, privacy: .public)"
            )
            throw AttachmentStoreError.cannotRestoreFromTrash
        }

        let expectedDestination = paths.root.appendingPathComponent(snapshot.relativePath)
        let destinationDirectory = expectedDestination.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let finalDestination: URL
        if fileManager.fileExists(atPath: expectedDestination.path) {
            finalDestination = uniqueDestinationURL(
                in: destinationDirectory,
                preferredFilename: expectedDestination.lastPathComponent
            )
        } else {
            finalDestination = expectedDestination
        }

        do {
            try fileManager.moveItem(at: trashedURL, to: finalDestination)
            try validateIntegrity(of: finalDestination, expectedSHA256: snapshot.sha256)
        } catch {
            if fileManager.fileExists(atPath: finalDestination.path) {
                try? fileManager.moveItem(at: finalDestination, to: trashedURL)
            }
            AppLogger.attachment.error(
                "restore deleted attachment failed before model restore. attachment=\(snapshot.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }

        let ownerType = AttachmentOwnerType(rawValue: snapshot.ownerTypeRaw) ?? .task
        let restoredRelativePath = Self.relativePath(from: paths.root, to: finalDestination)
        let restoredFilename = finalDestination.lastPathComponent
        let now = Date()

        let attachment = AttachmentEntity(
            id: snapshot.id,
            ownerType: ownerType,
            ownerID: snapshot.ownerID,
            relativePath: restoredRelativePath,
            originalFilename: restoredFilename,
            mimeType: snapshot.mimeType,
            byteSize: snapshot.byteSize,
            sha256: snapshot.sha256,
            isArchived: snapshot.isArchived,
            createdAt: snapshot.createdAt,
            updatedAt: now
        )
        context.insert(attachment)

        let taskSnapshot = try applyTaskAttachmentDelta(
            ownerType: attachment.ownerType,
            ownerID: attachment.ownerID,
            occurredAt: now,
            delta: 1,
            in: context
        )
        let projectSnapshot = try touchProjectIfNeeded(
            ownerType: attachment.ownerType,
            ownerID: attachment.ownerID,
            occurredAt: now,
            in: context
        )

        do {
            try context.save()
            updateTaskAttachmentIndexIfNeeded(
                action: .upsert(attachment),
                ownerType: attachment.ownerType,
                ownerID: attachment.ownerID,
                in: context
            )
            return attachment
        } catch {
            context.delete(attachment)
            restoreTaskMutation(taskSnapshot)
            restoreProjectMutation(projectSnapshot)
            if fileManager.fileExists(atPath: finalDestination.path) {
                try? fileManager.moveItem(at: finalDestination, to: trashedURL)
            }
            AppLogger.attachment.error(
                "restore deleted attachment failed while saving. attachment=\(snapshot.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func delete(
        _ attachment: AttachmentEntity,
        in context: ModelContext,
        captureUndoSnapshot: Bool
    ) throws -> DeletedAttachmentSnapshot? {
        var snapshot: DeletedAttachmentSnapshot?
        if captureUndoSnapshot {
            snapshot = DeletedAttachmentSnapshot(
                id: attachment.id,
                ownerTypeRaw: attachment.ownerTypeRaw,
                ownerID: attachment.ownerID,
                relativePath: attachment.relativePath,
                originalFilename: attachment.originalFilename,
                mimeType: attachment.mimeType,
                byteSize: attachment.byteSize,
                sha256: attachment.sha256,
                isArchived: attachment.isArchived,
                createdAt: attachment.createdAt,
                updatedAt: attachment.updatedAt,
                trashedFileURL: nil
            )
        }

        if let url = try? resolve(attachment), fileManager.fileExists(atPath: url.path) {
            let trashedURL = try moveItemToTrash(url)
            snapshot?.trashedFileURL = trashedURL
        }

        let now = Date()
        let taskSnapshot = try applyTaskAttachmentDelta(
            ownerType: attachment.ownerType,
            ownerID: attachment.ownerID,
            occurredAt: now,
            delta: -1,
            in: context
        )
        let projectSnapshot = try touchProjectIfNeeded(
            ownerType: attachment.ownerType,
            ownerID: attachment.ownerID,
            occurredAt: now,
            in: context
        )
        context.delete(attachment)

        do {
            try context.save()
            updateTaskAttachmentIndexIfNeeded(
                action: .remove(attachment.id),
                ownerType: attachment.ownerType,
                ownerID: attachment.ownerID,
                in: context
            )
            return snapshot
        } catch {
            if let url = snapshot?.trashedFileURL,
               fileManager.fileExists(atPath: url.path) {
                let restoreURL = try? restoreURLForDeletedAttachment(
                    attachment,
                    originalRelativePath: snapshot?.relativePath
                )
                if let restoreURL {
                    try? fileManager.createDirectory(
                        at: restoreURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? fileManager.moveItem(at: url, to: restoreURL)
                }
            }
            restoreTaskMutation(taskSnapshot)
            restoreProjectMutation(projectSnapshot)
            context.insert(attachment)
            AppLogger.attachment.error(
                "delete attachment failed. attachment=\(attachment.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func moveItemToTrash(_ url: URL) throws -> URL {
        var trashedURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)
        return (trashedURL as URL?) ?? url
    }

    private func uniqueDestinationURL(in directory: URL, preferredFilename: String) -> URL {
        let ext = (preferredFilename as NSString).pathExtension
        let rawBase = (preferredFilename as NSString).deletingPathExtension
        let base = rawBase.isEmpty ? "Attachment" : rawBase

        let firstCandidate = directory.appendingPathComponent(preferredFilename)
        if !fileManager.fileExists(atPath: firstCandidate.path) {
            return firstCandidate
        }

        for index in 1...9999 {
            let suffix = String(format: "_%03d", index)
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(base)\(suffix)"
            } else {
                candidateName = "\(base)\(suffix).\(ext)"
            }

            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let fallbackName = "\(base)_\(UUID().uuidString)\(ext.isEmpty ? "" : ".\(ext)")"
        return directory.appendingPathComponent(fallbackName)
    }

    private static func relativePath(from root: URL, to file: URL) -> String {
        var rootPath = root.path
        if !rootPath.hasSuffix("/") {
            rootPath += "/"
        }

        if file.path.hasPrefix(rootPath) {
            return String(file.path.dropFirst(rootPath.count))
        }

        return file.path
    }

    private enum TaskAttachmentIndexMutation {
        case upsert(AttachmentEntity)
        case remove(UUID)
    }

    private func updateTaskAttachmentIndexIfNeeded(
        action: TaskAttachmentIndexMutation,
        ownerType: AttachmentOwnerType,
        ownerID: UUID,
        in context: ModelContext
    ) {
        guard ownerType == .task else { return }
        guard let paths = storage.paths else { return }

        do {
            let projectIDs = try visibleProjectIDsForTaskOwner(ownerID, in: context)
            guard !projectIDs.isEmpty else {
                return
            }

            for projectID in projectIDs {
                switch action {
                case .upsert(let attachment):
                    try ProjectTaskAttachmentIndexStore.upsert(
                        attachment: attachment,
                        taskID: ownerID,
                        projectID: projectID,
                        paths: paths,
                        fileManager: fileManager
                    )
                case .remove(let attachmentID):
                    try ProjectTaskAttachmentIndexStore.remove(
                        attachmentID: attachmentID,
                        projectID: projectID,
                        paths: paths,
                        fileManager: fileManager
                    )
                }
            }
        } catch {
            AppLogger.attachment.error(
                "update task attachment index failed. owner=\(ownerID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func applyTaskAttachmentDelta(
        ownerType: AttachmentOwnerType,
        ownerID: UUID,
        occurredAt: Date,
        delta: Int,
        in context: ModelContext
    ) throws -> TaskMutationSnapshot? {
        guard ownerType == .task else {
            return nil
        }

        let taskContentDescriptor = FetchDescriptor<TaskContent>(
            predicate: #Predicate { $0.id == ownerID }
        )
        let taskItemDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == ownerID }
        )

        let taskContent = try context.fetch(taskContentDescriptor).first
        let taskItem = try context.fetch(taskItemDescriptor).first

        guard taskContent != nil || taskItem != nil else {
            return nil
        }

        let snapshot = TaskMutationSnapshot(
            taskContent: taskContent,
            taskItem: taskItem,
            taskContentAttachmentCount: taskContent?.attachmentCount,
            taskContentLocalUpdatedAt: taskContent?.localUpdatedAt,
            taskContentWasDirty: taskContent?.isDirty,
            taskItemAttachmentCount: taskItem?.attachmentCount,
            taskItemLocalUpdatedAt: taskItem?.localUpdatedAt,
            taskItemWasDirty: taskItem?.isDirty
        )

        if let taskContent {
            taskContent.attachmentCount = max(0, taskContent.attachmentCount + delta)
            taskContent.localUpdatedAt = occurredAt
            taskContent.isDirty = true
        }

        if let taskItem {
            taskItem.attachmentCount = max(0, taskItem.attachmentCount + delta)
            taskItem.localUpdatedAt = occurredAt
            taskItem.isDirty = true
        }

        return snapshot
    }

    private func restoreTaskMutation(_ snapshot: TaskMutationSnapshot?) {
        guard let snapshot else { return }

        if let taskContent = snapshot.taskContent {
            if let attachmentCount = snapshot.taskContentAttachmentCount {
                taskContent.attachmentCount = attachmentCount
            }
            if let localUpdatedAt = snapshot.taskContentLocalUpdatedAt {
                taskContent.localUpdatedAt = localUpdatedAt
            }
            if let wasDirty = snapshot.taskContentWasDirty {
                taskContent.isDirty = wasDirty
            }
        }

        if let taskItem = snapshot.taskItem {
            if let attachmentCount = snapshot.taskItemAttachmentCount {
                taskItem.attachmentCount = attachmentCount
            }
            if let localUpdatedAt = snapshot.taskItemLocalUpdatedAt {
                taskItem.localUpdatedAt = localUpdatedAt
            }
            if let wasDirty = snapshot.taskItemWasDirty {
                taskItem.isDirty = wasDirty
            }
        }
    }

    private func touchProjectIfNeeded(
        ownerType: AttachmentOwnerType,
        ownerID: UUID,
        occurredAt: Date,
        in context: ModelContext
    ) throws -> ProjectMutationSnapshot? {
        let projectIDs: [UUID]
        switch ownerType {
        case .project:
            projectIDs = [ownerID]
        case .task:
            projectIDs = try visibleProjectIDsForTaskOwner(ownerID, in: context)
        }

        guard !projectIDs.isEmpty else { return nil }

        let descriptor = FetchDescriptor<ProjectRecord>(
            predicate: #Predicate { projectIDs.contains($0.id) }
        )
        let projects = try context.fetch(descriptor)
        guard !projects.isEmpty else { return nil }

        var snapshots: [(project: ProjectRecord, updatedAt: Date)] = []
        for project in projects {
            snapshots.append((project: project, updatedAt: project.updatedAt))
            project.updatedAt = occurredAt
        }
        return ProjectMutationSnapshot(projects: snapshots)
    }

    private func restoreProjectMutation(_ snapshot: ProjectMutationSnapshot?) {
        guard let snapshot else { return }
        for snapshotEntry in snapshot.projects {
            snapshotEntry.project.updatedAt = snapshotEntry.updatedAt
        }
    }

    private func visibleProjectIDsForTaskOwner(
        _ taskID: UUID,
        in context: ModelContext
    ) throws -> [UUID] {
        var projectIDs: [UUID] = []

        if let runtimeSnapshot = runtimeSnapshotProvider() {
            if let location = runtimeSnapshot.taskLocation(for: taskID) {
                projectIDs.append(runtimeSnapshot.projects[location.projectIndex].id)
            }

            if projectIDs.isEmpty,
               let reminderExternalIdentifier = resolvedTaskReminderExternalIdentifier(
                   taskID,
                   in: context
               ) {
                projectIDs.append(
                    contentsOf: runtimeProjectIDs(
                        matchingReminderExternalIdentifier: reminderExternalIdentifier,
                        in: runtimeSnapshot
                    )
                )
            }
        }

        if projectIDs.isEmpty, let paths = storage.paths {
            projectIDs.append(
                contentsOf: ProjectTaskAttachmentIndexStore.projectIDs(
                    containingTaskID: taskID,
                    paths: paths,
                    fileManager: fileManager
                )
            )
        }

        if projectIDs.isEmpty,
           let ownerProjectID = TaskIdentityBridgeStore.record(for: taskID)?.ownerProjectID {
            projectIDs.append(ownerProjectID)
        }

        var ordered: [UUID] = []
        var seen: Set<UUID> = []
        for projectID in projectIDs where seen.insert(projectID).inserted {
            ordered.append(projectID)
        }
        return ordered
    }

    private func resolvedTaskReminderExternalIdentifier(
        _ taskID: UUID,
        in context: ModelContext
    ) -> String? {
        let descriptor = FetchDescriptor<TaskContent>(
            predicate: #Predicate { $0.id == taskID }
        )
        if let task = try? context.fetch(descriptor).first,
           let reminderExternalIdentifier = normalizedReminderExternalIdentifier(
               task.reminderExternalIdentifier
           ) {
            return reminderExternalIdentifier
        }
        return normalizedReminderExternalIdentifier(
            TaskIdentityBridgeStore.reminderExternalIdentifier(for: taskID)
        )
    }

    private func runtimeProjectIDs(
        matchingReminderExternalIdentifier reminderExternalIdentifier: String,
        in runtimeSnapshot: OutlineProjectionRuntimeSnapshot
    ) -> [UUID] {
        runtimeSnapshot.projects.compactMap { project in
            project.document.flatten().contains(where: { entry in
                entry.node.type.isTask
                    && normalizedReminderExternalIdentifier(
                        entry.node.reminderExternalIdentifier
                    ) == reminderExternalIdentifier
            }) ? project.id : nil
        }
    }

    private func normalizedReminderExternalIdentifier(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func restoreURLForDeletedAttachment(
        _ attachment: AttachmentEntity,
        originalRelativePath: String?
    ) throws -> URL {
        guard let paths = storage.paths else {
            AppLogger.attachment.error("restore URL lookup failed because container is unavailable")
            throw AttachmentStoreError.containerUnavailable
        }

        if let originalRelativePath {
            return paths.root.appendingPathComponent(originalRelativePath)
        }

        return paths.root.appendingPathComponent(attachment.relativePath)
    }

    private func validateIntegrity(of url: URL, expectedSHA256: String) throws {
        let actualSHA256 = try Self.sha256(of: url)
        guard actualSHA256 == expectedSHA256 else {
            AppLogger.attachment.error(
                "attachment integrity check failed. file=\(url.path, privacy: .public) expected=\(expectedSHA256, privacy: .public) actual=\(actualSHA256, privacy: .public)"
            )
            throw AttachmentStoreError.integrityCheckFailed
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 64 * 1024)
            if data.isEmpty {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
