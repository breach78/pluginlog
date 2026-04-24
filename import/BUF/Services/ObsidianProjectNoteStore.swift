import Foundation

struct ProjectNoteIdentity: Sendable {
    let projectID: UUID
    let projectTitle: String
}

actor ObsidianProjectNoteStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private var fileURLCache: [UUID: URL] = [:]
    private var didBuildIndex = false

    init(rootURL: URL, fileManager: FileManager = FileManager()) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    func prepareDirectory() throws {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            AppLogger.notes.error(
                "prepare notes directory failed. root=\(self.rootURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    func readOrCreateNote(for identity: ProjectNoteIdentity, fallback: String) throws -> String {
        try prepareDirectory()
        let fileURL = try resolveFileURL(for: identity)
        do {
            let contents = try readText(at: fileURL)
            return extractNoteBody(from: contents, expectedProjectID: identity.projectID)
        } catch {
            guard isFileNotFound(error) else { throw error }
        }

        let canonical = canonicalFileURL(for: identity)
        if let recoveredURL = try noteFileURLs(for: identity.projectID).max(by: {
            modificationDate(for: $0) < modificationDate(for: $1)
        }) {
            let normalizedURL = try normalizeResolvedFileURL(
                recoveredURL,
                canonical: canonical,
                identity: identity
            )
            let contents = try readText(at: normalizedURL)
            return extractNoteBody(from: contents, expectedProjectID: identity.projectID)
        }

        try write(renderManagedNote(fallback, for: identity), to: canonical)
        return fallback
    }

    func writeNote(_ note: String, for identity: ProjectNoteIdentity) throws {
        try prepareDirectory()
        let fileURL = try resolveFileURL(for: identity)
        try write(renderManagedNote(note, for: identity), to: fileURL)
    }

    func deleteNote(for identity: ProjectNoteIdentity) throws {
        do {
            try prepareDirectory()
            let fileURL = try resolveFileURL(for: identity)

            var trashedURL: NSURL?
            do {
                try fileManager.trashItem(at: fileURL, resultingItemURL: &trashedURL)
            } catch {
                guard isFileNotFound(error) else { throw error }
            }

            fileURLCache[identity.projectID] = nil
        } catch {
            AppLogger.notes.error(
                "delete note failed. project=\(identity.projectID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func write(_ note: String, to fileURL: URL) throws {
        let data = Data(note.utf8)
        let directory = fileURL.deletingLastPathComponent()
        let tempURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        let backupName = ".\(fileURL.lastPathComponent).bak"
        let backupURL = directory.appendingPathComponent(backupName)

        do {
            try data.write(to: tempURL, options: .atomic)

            do {
                _ = try fileManager.replaceItemAt(
                    fileURL,
                    withItemAt: tempURL,
                    backupItemName: backupName,
                    options: [.usingNewMetadataOnly]
                )
                if itemExists(at: backupURL) {
                    try? fileManager.removeItem(at: backupURL)
                }
            } catch {
                if isFileNotFound(error) {
                    try fileManager.moveItem(at: tempURL, to: fileURL)
                } else {
                    throw error
                }
            }
        } catch {
            if !itemExists(at: fileURL),
               itemExists(at: backupURL) {
                try? fileManager.moveItem(at: backupURL, to: fileURL)
            }
            if itemExists(at: tempURL) {
                try? fileManager.removeItem(at: tempURL)
            }
            AppLogger.notes.error(
                "write note failed. file=\(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func readText(at fileURL: URL) throws -> String {
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            if String(data: data, encoding: .utf8) == nil {
                AppLogger.notes.error(
                    "note file contains invalid UTF-8; falling back to lossy decode. file=\(fileURL.path, privacy: .public)"
                )
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    private func resolveFileURL(for identity: ProjectNoteIdentity) throws -> URL {
        let canonical = canonicalFileURL(for: identity)
        if let cachedURL = fileURLCache[identity.projectID],
           itemExists(at: cachedURL) {
            return try normalizeResolvedFileURL(
                cachedURL,
                canonical: canonical,
                identity: identity
            )
        }

        if fileURLCache[identity.projectID] != nil {
            fileURLCache[identity.projectID] = nil
            didBuildIndex = false
        }

        try buildIndexIfNeeded()
        if let indexedURL = fileURLCache[identity.projectID],
           itemExists(at: indexedURL) {
            return try normalizeResolvedFileURL(
                indexedURL,
                canonical: canonical,
                identity: identity
            )
        }

        fileURLCache[identity.projectID] = canonical
        return canonical
    }

    private func buildIndexIfNeeded() throws {
        guard !didBuildIndex else { return }
        didBuildIndex = true

        fileURLCache.removeAll(keepingCapacity: true)

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            AppLogger.notes.error(
                "build notes index failed. root=\(self.rootURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }

        for fileURL in urls where fileURL.pathExtension.lowercased() == "md" {
            guard let projectID = parseProjectID(fromFilename: fileURL.deletingPathExtension().lastPathComponent) else {
                continue
            }

            if let existingURL = fileURLCache[projectID] {
                let existingDate = (try? existingURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let incomingDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if incomingDate > existingDate {
                    fileURLCache[projectID] = fileURL
                }
            } else {
                fileURLCache[projectID] = fileURL
            }
        }
    }

    private func parseProjectID(fromFilename filename: String) -> UUID? {
        if let uuid = UUID(uuidString: filename) {
            return uuid
        }

        guard let suffix = filename.split(separator: "__").last else {
            return nil
        }

        return UUID(uuidString: String(suffix))
    }

    private func canonicalFileURL(for identity: ProjectNoteIdentity) -> URL {
        rootURL.appendingPathComponent("\(identity.projectID.uuidString.lowercased()).md")
    }

    private func normalizeResolvedFileURL(
        _ resolvedURL: URL,
        canonical: URL,
        identity: ProjectNoteIdentity
    ) throws -> URL {
        let projectID = identity.projectID
        let candidateURLs = try noteFileURLs(for: projectID)
        guard !candidateURLs.isEmpty else {
            fileURLCache[projectID] = canonical
            return canonical
        }

        let preferredURL = candidateURLs.max(by: {
            modificationDate(for: $0) < modificationDate(for: $1)
        }) ?? resolvedURL

        if preferredURL != canonical || candidateURLs.count > 1 {
            let contents = try readText(at: preferredURL)
            let normalizedBody = extractNoteBody(from: contents, expectedProjectID: projectID)
            try write(renderManagedNote(normalizedBody, for: identity), to: canonical)

            for url in candidateURLs where url != canonical {
                if itemExists(at: url) {
                    try? fileManager.removeItem(at: url)
                }
            }
        }

        fileURLCache[projectID] = canonical
        return canonical
    }

    private func noteFileURLs(for projectID: UUID) throws -> [URL] {
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            AppLogger.notes.error(
                "enumerate note files failed. root=\(self.rootURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }

        return urls.filter { fileURL in
            guard fileURL.pathExtension.lowercased() == "md" else { return false }
            return parseProjectID(fromFilename: fileURL.deletingPathExtension().lastPathComponent) == projectID
        }
    }

    private func modificationDate(for fileURL: URL) -> Date {
        (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private func itemExists(at url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) ?? false
    }

    private func isFileNotFound(_ error: Error) -> Bool {
        guard let cocoaError = error as? CocoaError else { return false }
        switch cocoaError.code {
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return true
        default:
            return false
        }
    }

    private func renderManagedNote(_ note: String, for identity: ProjectNoteIdentity) -> String {
        let body = extractNoteBody(from: note, expectedProjectID: identity.projectID)
        let frontMatter = """
        ---
        title: "\(yamlEscaped(identity.projectTitle))"
        brain_unfog_project_id: "\(identity.projectID.uuidString.lowercased())"
        ---
        """

        guard !body.isEmpty else { return frontMatter + "\n" }
        return frontMatter + "\n\n" + body
    }

    private func extractNoteBody(from contents: String, expectedProjectID: UUID) -> String {
        guard contents.hasPrefix("---\n") else { return contents }
        guard let closingRange = contents.range(of: "\n---\n") else { return contents }

        let frontMatterBody = String(contents[contents.index(contents.startIndex, offsetBy: 4)..<closingRange.lowerBound])
        guard frontMatterProjectID(from: frontMatterBody) == expectedProjectID.uuidString.lowercased() else {
            return contents
        }

        var body = String(contents[closingRange.upperBound...])
        if body.hasPrefix("\n") {
            body.removeFirst()
        }
        return body
    }

    private func yamlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func frontMatterProjectID(from frontMatterBody: String) -> String? {
        for rawLine in frontMatterBody.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("brain_unfog_project_id:") else { continue }

            let value = line.dropFirst("brain_unfog_project_id:".count)
                .trimmingCharacters(in: .whitespaces)
            let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return unquoted.lowercased()
        }

        return nil
    }

}
