import CryptoKit
import Foundation

struct ReminderNoteCodec {
    struct ParsedNote: Equatable {
        var body: String
        var trailer: Trailer

        var attachmentCount: Int { 0 }
        var parentExternalIdentifier: String? { nil }
        var trailerRaw: String { "" }
    }

    struct Trailer: Equatable {
        static let empty = Trailer()

        var rawValue: String { "" }
    }

    static func parse(_ raw: String?) -> ParsedNote {
        guard let raw, !raw.isEmpty else {
            return ParsedNote(body: "", trailer: .empty)
        }
        let body = raw.normalizedReminderNoteLineBreaks().trimmingCharacters(in: .newlines)
        return ParsedNote(body: body, trailer: .empty)
    }

    static func parse(body: String, trailerRaw: String) -> ParsedNote {
        parse(compose(body: body, trailerRaw: trailerRaw))
    }

    static func compose(
        body: String,
        attachmentCount: Int,
        parentExternalIdentifier: String? = nil
    ) -> String {
        let _ = attachmentCount
        let _ = parentExternalIdentifier
        return compose(body: body, trailerRaw: "")
    }

    static func compose(
        body: String,
        trailer: Trailer
    ) -> String {
        let _ = trailer
        return compose(body: body, trailerRaw: "")
    }

    static func compose(
        body: String,
        trailerRaw: String
    ) -> String {
        let trimmedBody = body.normalizedReminderNoteLineBreaks().trimmingCharacters(in: .newlines)
        let trimmedTrailer = trailerRaw.normalizedReminderNoteLineBreaks().trimmingCharacters(in: .newlines)

        guard !trimmedTrailer.isEmpty else { return trimmedBody }
        guard !trimmedBody.isEmpty else { return trimmedTrailer }
        return [trimmedBody, trimmedTrailer].joined(separator: "\n")
    }
}

enum ReminderNoteSourceNode: Equatable {
    case bullet(text: String, depth: Int)
    case childAnchor(reminderExternalIdentifier: String, depth: Int)
}

typealias ReminderNoteAST = [ReminderNoteSourceNode]

struct ReminderNoteSourceDocument: Equatable {
    var normalizedText: String
    var ast: ReminderNoteAST
}

struct ReminderNoteSourceObservation: Equatable {
    var normalizedNoteText: String
    var normalizedNoteHash: String
    var remoteModifiedAt: Date?
}

enum ReminderAttachmentOwnerReference {
    private static let projectPrefix = "project:"
    private static let taskPrefix = "task:"
    private static let noteBulletPrefix = "note-bullet:"

    static func project(_ reminderListExternalIdentifier: String) -> String {
        projectPrefix + reminderListExternalIdentifier
    }

    static func task(_ reminderExternalIdentifier: String) -> String {
        taskPrefix + reminderExternalIdentifier
    }

    static func noteBullet(
        rootReminderExternalIdentifier: String,
        stablePath: [Int]
    ) -> String {
        noteBulletPrefix
            + rootReminderExternalIdentifier
            + ":"
            + stablePath.map(String.init).joined(separator: ".")
    }
}

struct ReminderAttachmentManifestEntry: Codable, Equatable {
    var attachmentID: UUID
    var ownerReference: String
    var relativePath: String
    var originalFilename: String
    var mimeType: String
    var byteSize: Int64
    var createdAt: Date
    var updatedAt: Date
}

enum ReminderAttachmentManifestCodec {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private static let decoder = JSONDecoder()

    static func encode(_ entries: [ReminderAttachmentManifestEntry]) -> String {
        let normalizedEntries = entries.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.attachmentID.uuidString < rhs.attachmentID.uuidString
            }
            return lhs.updatedAt < rhs.updatedAt
        }
        guard let data = try? encoder.encode(normalizedEntries),
              let raw = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return raw
    }

    static func decode(_ raw: String) -> [ReminderAttachmentManifestEntry] {
        guard let data = raw.data(using: .utf8),
              let decoded = try? decoder.decode([ReminderAttachmentManifestEntry].self, from: data)
        else {
            return []
        }
        return decoded
    }
}

struct ReminderNoteSourceConflictState: Codable, Equatable {
    var reminderExternalIdentifier: String
    var localNormalizedNoteText: String
    var localNormalizedNoteHash: String
    var remoteNormalizedNoteText: String
    var remoteNormalizedNoteHash: String
    var remoteModifiedAt: Date?

    var excerpt: String {
        "로컬 draft와 원격 note가 함께 바뀌어 자동 병합을 멈췄습니다."
    }

    var diffPreview: String {
        let localLines = Self.previewLines(from: localNormalizedNoteText)
        let remoteLines = Self.previewLines(from: remoteNormalizedNoteText)
        return (
            ["로컬:", localLines.map { "- \($0)" }.joined(separator: "\n"), "원격:", remoteLines.map { "+ \($0)" }.joined(separator: "\n")]
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
        )
    }

    private static func previewLines(from text: String) -> [String] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            return ["(비어 있음)"]
        }
        return normalized.components(separatedBy: .newlines)
    }
}

enum ReminderNoteSourceConflictStateCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode(_ state: ReminderNoteSourceConflictState?) -> String? {
        guard let state,
              let data = try? encoder.encode(state)
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ raw: String?) -> ReminderNoteSourceConflictState? {
        guard let raw,
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        return try? decoder.decode(ReminderNoteSourceConflictState.self, from: data)
    }
}

enum ReminderNoteSourceConflictDecision: Equatable {
    case noRemoteNoteChange(ReminderNoteSourceObservation)
    case applyRemote(ReminderNoteSourceObservation)
    case conflict(ReminderNoteSourceConflictState)
}

enum ReminderNoteSourceCodec {
    static let childAnchorPrefix = "☑t:"

    static func parseReminderRawNote(_ raw: String?) -> ReminderNoteSourceDocument {
        parse(ReminderNoteCodec.parse(raw).body)
    }

    static func normalizeReminderRawNote(_ raw: String?) -> String {
        parseReminderRawNote(raw).normalizedText
    }

    static func parse(_ raw: String?) -> ReminderNoteSourceDocument {
        let ast = parseAST(raw)
        return ReminderNoteSourceDocument(
            normalizedText: serialize(ast),
            ast: ast
        )
    }

    static func normalize(_ raw: String?) -> String {
        parse(raw).normalizedText
    }

    static func bulletNoteText(from raw: String?) -> String {
        let bulletOnlyAST = parseAST(raw).compactMap { node -> ReminderNoteSourceNode? in
            guard case let .bullet(text, depth) = node else { return nil }
            return .bullet(text: text, depth: depth)
        }
        return serialize(bulletOnlyAST)
    }

    static func parseAST(_ raw: String?) -> ReminderNoteAST {
        guard let raw, !raw.isEmpty else { return [] }

        return raw
            .normalizedReminderNoteLineBreaks()
            .components(separatedBy: .newlines)
            .compactMap(parseLine)
    }

    static func serialize(_ ast: ReminderNoteAST) -> String {
        ast.compactMap(serializeLine).joined(separator: "\n")
    }

    private static func parseLine(_ rawLine: String) -> ReminderNoteSourceNode? {
        let normalizedLine = rawLine.removingTrailingReminderNoteWhitespace()
        guard !normalizedLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let depth = normalizedLine.leadingReminderNoteSpaceCount()
        let body = String(normalizedLine.dropFirst(depth))

        if let reminderExternalIdentifier = parseAnchorIdentifier(body) {
            return .childAnchor(
                reminderExternalIdentifier: reminderExternalIdentifier,
                depth: depth
            )
        }

        return .bullet(text: body, depth: depth)
    }

    private static func serializeLine(_ node: ReminderNoteSourceNode) -> String? {
        switch node {
        case let .bullet(text, depth):
            let normalizedText = text
                .normalizedReminderNoteLineBreaks()
                .components(separatedBy: .newlines)
                .joined(separator: " ")
                .removingTrailingReminderNoteWhitespace()
            guard !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return String(repeating: " ", count: max(0, depth)) + normalizedText

        case let .childAnchor(reminderExternalIdentifier, depth):
            let normalizedIdentifier = reminderExternalIdentifier.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard isValidAnchorIdentifier(normalizedIdentifier) else { return nil }
            return String(repeating: " ", count: max(0, depth))
                + childAnchorPrefix
                + normalizedIdentifier
        }
    }

    private static func parseAnchorIdentifier(_ body: String) -> String? {
        guard body.hasPrefix(childAnchorPrefix) else { return nil }
        let reminderExternalIdentifier = String(body.dropFirst(childAnchorPrefix.count))
        guard isValidAnchorIdentifier(reminderExternalIdentifier) else { return nil }
        return reminderExternalIdentifier
    }

    private static func isValidAnchorIdentifier(_ reminderExternalIdentifier: String) -> Bool {
        !reminderExternalIdentifier.isEmpty
            && reminderExternalIdentifier.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}

enum ReminderNoteSourceConflictGate {
    static func evaluate(
        reminderExternalIdentifier: String,
        localNormalizedNoteText: String,
        remoteRawNote: String?,
        runtimeState: ReminderTaskSourceRuntimeState?
    ) -> ReminderNoteSourceConflictDecision {
        let remoteNormalizedNoteText = ReminderNoteSourceCodec.normalizeReminderRawNote(remoteRawNote)
        let remoteObservation = ReminderNoteSourceObservation(
            normalizedNoteText: remoteNormalizedNoteText,
            normalizedNoteHash: ReminderNoteSourceMutationService.hash(for: remoteNormalizedNoteText),
            remoteModifiedAt: runtimeState?.lastObservedReminderModifiedAt
        )
        return evaluate(
            reminderExternalIdentifier: reminderExternalIdentifier,
            localNormalizedNoteText: localNormalizedNoteText,
            remoteObservation: remoteObservation,
            runtimeState: runtimeState
        )
    }

    static func evaluate(
        reminderExternalIdentifier: String,
        localNormalizedNoteText: String,
        remoteObservation: ReminderNoteSourceObservation,
        runtimeState: ReminderTaskSourceRuntimeState?
    ) -> ReminderNoteSourceConflictDecision {
        let localNormalizedNoteHash = ReminderNoteSourceMutationService.hash(for: localNormalizedNoteText)

        if remoteObservation.normalizedNoteHash == runtimeState?.lastExportedNormalizedNoteHash
            || remoteObservation.normalizedNoteHash == runtimeState?.lastImportedNormalizedNoteHash
            || remoteObservation.normalizedNoteHash == localNormalizedNoteHash
        {
            return .noRemoteNoteChange(remoteObservation)
        }

        let hasLocalDraft = runtimeState?.lastImportedNormalizedNoteHash.map {
            $0 != localNormalizedNoteHash
        } ?? false
        guard hasLocalDraft else {
            return .applyRemote(remoteObservation)
        }

        return .conflict(
            ReminderNoteSourceConflictState(
                reminderExternalIdentifier: reminderExternalIdentifier,
                localNormalizedNoteText: localNormalizedNoteText,
                localNormalizedNoteHash: localNormalizedNoteHash,
                remoteNormalizedNoteText: remoteObservation.normalizedNoteText,
                remoteNormalizedNoteHash: remoteObservation.normalizedNoteHash,
                remoteModifiedAt: remoteObservation.remoteModifiedAt
            )
        )
    }
}

enum ReminderNoteSourceImportService {
    struct Result: Equatable {
        var children: [OutlineNode]
        var requiresNormalizationWrite: Bool
        var hasUnknownAnchors: Bool
    }

    static func materializeChildren(
        from document: ReminderNoteSourceDocument,
        preservingExistingChildren existingChildren: [OutlineNode],
        parentReminderExternalIdentifier: String
    ) -> Result {
        var cursor = 0
        var consumedAnchorIdentifiers: Set<String> = []
        let materialized = materializeNodes(
            from: document.ast,
            cursor: &cursor,
            depth: 0,
            existingChildren: existingChildren,
            consumedAnchorIdentifiers: &consumedAnchorIdentifiers,
            parentReminderExternalIdentifier: parentReminderExternalIdentifier,
            parentPath: []
        )
        return Result(
            children: materialized.children,
            requiresNormalizationWrite: materialized.requiresNormalizationWrite && materialized.hasUnknownAnchors == false,
            hasUnknownAnchors: materialized.hasUnknownAnchors
        )
    }

    private struct MaterializedChildren {
        var children: [OutlineNode]
        var requiresNormalizationWrite: Bool
        var hasUnknownAnchors: Bool
    }

    private static func materializeNodes(
        from ast: ReminderNoteAST,
        cursor: inout Int,
        depth: Int,
        existingChildren: [OutlineNode],
        consumedAnchorIdentifiers: inout Set<String>,
        parentReminderExternalIdentifier: String,
        parentPath: [Int]
    ) -> MaterializedChildren {
        var children: [OutlineNode] = []
        let existingBulletChildren = existingChildren.filter { $0.type.isTask == false }
        var existingBulletIndex = 0
        let existingTaskChildrenInOrder = existingChildren.filter(\.type.isTask)
        var remainingTaskChildrenByReminderExternalIdentifier = Dictionary(
            grouping: existingTaskChildrenInOrder,
            by: reminderExternalIdentifier(for:)
        )
        var consumedTaskNodeIDs: Set<UUID> = []
        var requiresNormalizationWrite = false
        var hasUnknownAnchors = false

        while cursor < ast.count {
            let sourceNode = ast[cursor]
            let sourceDepth = sourceNode.depth
            if sourceDepth < depth {
                break
            }

            if sourceDepth > depth {
                guard children.isEmpty == false else {
                    cursor += 1
                    requiresNormalizationWrite = true
                    continue
                }
                let lastIndex = children.index(before: children.endIndex)
                guard children[lastIndex].type.isTask == false else {
                    skipMalformedInlineChildren(from: ast, cursor: &cursor, deeperThan: depth)
                    requiresNormalizationWrite = true
                    continue
                }
                let childPath = parentPath + [lastIndex]
                let nested = materializeNodes(
                    from: ast,
                    cursor: &cursor,
                    depth: sourceDepth,
                    existingChildren: children[lastIndex].children,
                    consumedAnchorIdentifiers: &consumedAnchorIdentifiers,
                    parentReminderExternalIdentifier: parentReminderExternalIdentifier,
                    parentPath: childPath
                )
                children[lastIndex].children = nested.children
                requiresNormalizationWrite = requiresNormalizationWrite || nested.requiresNormalizationWrite
                hasUnknownAnchors = hasUnknownAnchors || nested.hasUnknownAnchors
                continue
            }

            let nodePath = parentPath + [children.count]
            cursor += 1
            switch sourceNode {
            case let .bullet(text, _):
                let existing = existingBulletIndex < existingBulletChildren.count
                    ? existingBulletChildren[existingBulletIndex]
                    : nil
                if existing != nil {
                    existingBulletIndex += 1
                }

                var bulletNode = existing ?? OutlineNode(
                    id: ReminderProjectionIdentity.noteNodeID(
                        parentReminderExternalIdentifier: parentReminderExternalIdentifier,
                        path: nodePath,
                        text: text
                    ),
                    canonicalID: ReminderProjectionIdentity.noteNodeID(
                        parentReminderExternalIdentifier: parentReminderExternalIdentifier,
                        path: nodePath,
                        text: text
                    ),
                    text: text,
                    type: .bullet
                )
                bulletNode.text = text
                bulletNode.type = .bullet
                let nested = materializeNodes(
                    from: ast,
                    cursor: &cursor,
                    depth: depth + 1,
                    existingChildren: existing?.children ?? [],
                    consumedAnchorIdentifiers: &consumedAnchorIdentifiers,
                    parentReminderExternalIdentifier: parentReminderExternalIdentifier,
                    parentPath: nodePath
                )
                bulletNode.children = nested.children
                children.append(bulletNode)
                requiresNormalizationWrite = requiresNormalizationWrite || nested.requiresNormalizationWrite
                hasUnknownAnchors = hasUnknownAnchors || nested.hasUnknownAnchors

            case let .childAnchor(reminderExternalIdentifier, _):
                guard consumedAnchorIdentifiers.insert(reminderExternalIdentifier).inserted else {
                    skipMalformedInlineChildren(from: ast, cursor: &cursor, deeperThan: depth)
                    requiresNormalizationWrite = true
                    continue
                }

                if var bucket = remainingTaskChildrenByReminderExternalIdentifier[reminderExternalIdentifier],
                   let existingTask = bucket.first
                {
                    bucket.removeFirst()
                    if bucket.isEmpty {
                        remainingTaskChildrenByReminderExternalIdentifier.removeValue(
                            forKey: reminderExternalIdentifier
                        )
                    } else {
                        remainingTaskChildrenByReminderExternalIdentifier[reminderExternalIdentifier] = bucket
                    }
                    consumedTaskNodeIDs.insert(existingTask.id)
                    children.append(existingTask)
                } else {
                    let fallbackID = ReminderProjectionIdentity.noteNodeID(
                        parentReminderExternalIdentifier: parentReminderExternalIdentifier,
                        path: nodePath,
                        text: "\(ReminderNoteSourceCodec.childAnchorPrefix)\(reminderExternalIdentifier)"
                    )
                    children.append(
                        OutlineNode(
                            id: fallbackID,
                            canonicalID: fallbackID,
                            text: "\(ReminderNoteSourceCodec.childAnchorPrefix)\(reminderExternalIdentifier)",
                            type: .bullet
                        )
                    )
                    hasUnknownAnchors = true
                }
                if cursor < ast.count, ast[cursor].depth > depth {
                    skipMalformedInlineChildren(from: ast, cursor: &cursor, deeperThan: depth)
                    requiresNormalizationWrite = true
                }
            }
        }

        for existingTask in existingTaskChildrenInOrder where consumedTaskNodeIDs.contains(existingTask.id) == false {
            children.append(existingTask)
        }

        return MaterializedChildren(
            children: children,
            requiresNormalizationWrite: requiresNormalizationWrite,
            hasUnknownAnchors: hasUnknownAnchors
        )
    }

    private static func reminderExternalIdentifier(for node: OutlineNode) -> String {
        node.reminderExternalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func skipMalformedInlineChildren(
        from ast: ReminderNoteAST,
        cursor: inout Int,
        deeperThan depth: Int
    ) {
        while cursor < ast.count, ast[cursor].depth > depth {
            cursor += 1
        }
    }
}

struct ReminderMetadataMutationPlan: Equatable {
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    var hasExplicitTime: Bool
    var recurrence: OutlinerRecurrenceSample?
    var priority: Int
}

enum ReminderMetadataMutationService {
    static func plan(for projection: OutlinerReminderProjection) -> ReminderMetadataMutationPlan {
        ReminderMetadataMutationPlan(
            title: projection.title,
            isCompleted: projection.taskLine.marker == .done,
            dueDate: projection.syncContract.reminderPayload.dueDate,
            hasExplicitTime: projection.syncContract.reminderPayload.hasExplicitTime,
            recurrence: projection.syncContract.reminderPayload.recurrence,
            priority: projection.syncContract.reminderPayload.priority
        )
    }
}

struct ReminderNoteSourceMutationPlan: Equatable {
    var document: ReminderNoteSourceDocument
    var normalizedNoteHash: String

    var normalizedNoteText: String {
        document.normalizedText
    }
}

enum ReminderNoteSourceMutationService {
    static func insertingChildAnchor(
        _ reminderExternalIdentifier: String,
        into noteText: String,
        at insertionSlot: Int? = nil
    ) -> ReminderNoteSourceDocument? {
        guard let normalizedReminderExternalIdentifier = normalizedAnchorIdentifier(reminderExternalIdentifier) else {
            return nil
        }

        var ast = ReminderNoteSourceCodec.parse(noteText).ast
        let directChildStartIndexes = ast.enumerated().compactMap { index, node in
            node.depth == 0 ? index : nil
        }
        let requestedSlot = insertionSlot ?? directChildStartIndexes.count
        let normalizedSlot = min(max(0, requestedSlot), directChildStartIndexes.count)
        let insertionIndex = normalizedSlot < directChildStartIndexes.count
            ? directChildStartIndexes[normalizedSlot]
            : ast.count
        ast.insert(
            .childAnchor(
                reminderExternalIdentifier: normalizedReminderExternalIdentifier,
                depth: 0
            ),
            at: insertionIndex
        )
        return ReminderNoteSourceDocument(
            normalizedText: ReminderNoteSourceCodec.serialize(ast),
            ast: ast
        )
    }

    static func removingChildAnchor(
        _ reminderExternalIdentifier: String,
        from noteText: String
    ) -> ReminderNoteSourceDocument? {
        guard let normalizedReminderExternalIdentifier = normalizedAnchorIdentifier(reminderExternalIdentifier) else {
            return nil
        }

        let document = ReminderNoteSourceCodec.parse(noteText)
        var didRemove = false
        let updatedAST = document.ast.filter { node in
            guard case let .childAnchor(existingReminderExternalIdentifier, _) = node else {
                return true
            }
            guard existingReminderExternalIdentifier == normalizedReminderExternalIdentifier, didRemove == false else {
                return true
            }
            didRemove = true
            return false
        }
        guard didRemove else { return nil }

        return ReminderNoteSourceDocument(
            normalizedText: ReminderNoteSourceCodec.serialize(updatedAST),
            ast: updatedAST
        )
    }

    static func plan(
        for taskNode: OutlineNode,
        reminderExternalIdentifierResolver: (OutlineNode) -> String?
    ) -> ReminderNoteSourceMutationPlan {
        let ast = sourceAST(
            from: taskNode.children,
            depth: 0,
            reminderExternalIdentifierResolver: reminderExternalIdentifierResolver
        )
        let document = ReminderNoteSourceDocument(
            normalizedText: ReminderNoteSourceCodec.serialize(ast),
            ast: ast
        )
        return ReminderNoteSourceMutationPlan(
            document: document,
            normalizedNoteHash: hash(for: document.normalizedText)
        )
    }

    static func hash(for normalizedNoteText: String) -> String {
        let digest = SHA256.hash(data: Data(normalizedNoteText.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func shouldSkipWrite(
        exportHash: String,
        runtimeState: ReminderTaskSourceRuntimeState?,
        remoteModifiedAt: Date?
    ) -> Bool {
        guard let runtimeState else { return false }
        return runtimeState.lastImportedNormalizedNoteHash == exportHash
            && runtimeState.lastObservedReminderModifiedAt == remoteModifiedAt
    }

    private static func sourceAST(
        from nodes: [OutlineNode],
        depth: Int,
        reminderExternalIdentifierResolver: (OutlineNode) -> String?
    ) -> ReminderNoteAST {
        var ast: ReminderNoteAST = []

        for node in nodes {
            if node.type.isTask {
                guard let reminderExternalIdentifier = normalizedAnchorIdentifier(
                    reminderExternalIdentifierResolver(node)
                ) else {
                    continue
                }
                ast.append(
                    .childAnchor(
                        reminderExternalIdentifier: reminderExternalIdentifier,
                        depth: depth
                    )
                )
                continue
            }

            let normalizedText = node.text
                .normalizedReminderNoteLineBreaks()
                .components(separatedBy: .newlines)
                .joined(separator: " ")
                .removingTrailingReminderNoteWhitespace()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty {
                ast.append(.bullet(text: normalizedText, depth: depth))
            }

            guard !node.children.isEmpty else { continue }
            ast.append(
                contentsOf: sourceAST(
                    from: node.children,
                    depth: depth + 1,
                    reminderExternalIdentifierResolver: reminderExternalIdentifierResolver
                )
            )
        }

        return ast
    }

    private static func normalizedAnchorIdentifier(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

enum ReminderSubtreeCommitBoundary: Hashable, Equatable {
    case projectTitle
    case taskSubtree(contentID: UUID)

    var contentID: UUID? {
        guard case let .taskSubtree(contentID) = self else { return nil }
        return contentID
    }
}

enum ReminderSubtreeCommitBoundaryEngine {
    static func editingBoundary(
        for nodeID: UUID?,
        in document: OutlineDocument,
        isProjectTitleFocused: Bool
    ) -> ReminderSubtreeCommitBoundary? {
        if isProjectTitleFocused {
            return .projectTitle
        }
        guard let nodeID,
              let contentID = rootTaskContentID(for: nodeID, in: document)
        else {
            return nil
        }
        return .taskSubtree(contentID: contentID)
    }

    static func rootTaskContentID(for nodeID: UUID, in document: OutlineDocument) -> UUID? {
        var currentID: UUID? = nodeID

        while let resolvedID = currentID,
              let node = OutlineNodeTreeNavigator.findNode(id: resolvedID, in: document.rootNodes)
        {
            if node.type.isTask {
                return node.canonicalID
            }
            currentID = OutlineNodeTreeNavigator.parentOf(id: resolvedID, in: document.rootNodes)
        }

        return nil
    }
}

enum AppFeatureMutationService {
    static func taskFeatureRecord(
        reminderExternalIdentifier: String,
        featureSidecar: OutlinerTaskSidecarMetadata,
        existing: ReminderTaskFeatureSidecarRecord? = nil,
        attachmentManifestRaw: String? = nil,
        ownedCalendarEventExternalIdentifier: String? = nil,
        boardStageRaw: String? = nil,
        importanceRaw: String? = nil,
        isFlagged: Bool? = nil,
        completedWorkUnits: Int? = nil,
        completedWorkUnitDatesRaw: String? = nil,
        preparationScheduleOverridesRaw: String? = nil,
        now: Date = .now
    ) -> ReminderTaskFeatureSidecarRecord {
        ReminderTaskFeatureSidecarRecord(
            reminderExternalIdentifier: reminderExternalIdentifier,
            attachmentManifestRaw: attachmentManifestRaw ?? existing?.attachmentManifestRaw ?? "",
            scheduledDurationMinutes: featureSidecar.scheduledDurationMinutes,
            ownedCalendarEventExternalIdentifier: ownedCalendarEventExternalIdentifier
                ?? existing?.ownedCalendarEventExternalIdentifier,
            boardStageRaw: boardStageRaw ?? existing?.boardStageRaw,
            importanceRaw: importanceRaw ?? existing?.importanceRaw,
            isFlagged: isFlagged ?? existing?.isFlagged ?? false,
            requiredWorkDays: max(0, featureSidecar.requiredWorkDays),
            completedWorkUnits: max(0, completedWorkUnits ?? existing?.completedWorkUnits ?? 0),
            completedWorkUnitDatesRaw: completedWorkUnitDatesRaw
                ?? existing?.completedWorkUnitDatesRaw
                ?? "",
            preparationScheduleOverridesRaw: preparationScheduleOverridesRaw
                ?? existing?.preparationScheduleOverridesRaw
                ?? "",
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }
}

enum ReminderWorkspaceStructureMutationService {
    static func record(
        orderedReminderListExternalIdentifiers: [String],
        existing: ReminderWorkspaceStructureRecord? = nil,
        now: Date = .now
    ) -> ReminderWorkspaceStructureRecord {
        ReminderWorkspaceStructureRecord(
            orderedReminderListExternalIdentifiers: orderedReminderListExternalIdentifiers,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }
}

enum ReminderProjectTaskOrderMutationService {
    static func record(
        reminderListExternalIdentifier: String,
        orderedTopLevelReminderExternalIdentifiers: [String],
        existing: ReminderProjectTaskOrderRecord? = nil,
        now: Date = .now
    ) -> ReminderProjectTaskOrderRecord {
        ReminderProjectTaskOrderRecord(
            reminderListExternalIdentifier: reminderListExternalIdentifier,
            orderedTopLevelReminderExternalIdentifiers: orderedTopLevelReminderExternalIdentifiers,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }
}

enum ReminderProjectFeatureMutationService {
    static func projectFeatureRecord(
        reminderListExternalIdentifier: String,
        projectNoteMarkdown: String,
        localStartDate: Date?,
        localDeadline: Date?,
        progressStageRaw: String?,
        boardOrder: Int?,
        existing: ReminderProjectFeatureSidecarRecord? = nil,
        attachmentManifestRaw: String? = nil,
        now: Date = .now
    ) -> ReminderProjectFeatureSidecarRecord {
        ReminderProjectFeatureSidecarRecord(
            reminderListExternalIdentifier: reminderListExternalIdentifier,
            projectNoteMarkdown: projectNoteMarkdown,
            localStartDate: localStartDate,
            localDeadline: localDeadline,
            progressStageRaw: progressStageRaw,
            boardOrder: boardOrder,
            attachmentManifestRaw: attachmentManifestRaw ?? existing?.attachmentManifestRaw ?? "",
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }
}

private extension String {
    func normalizedReminderNoteLineBreaks() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    func removingTrailingReminderNoteWhitespace() -> String {
        guard let index = lastIndex(where: { !$0.isWhitespace || $0 == "\n" || $0 == "\r" }) else {
            return ""
        }
        return String(prefix(through: index))
    }

    func leadingReminderNoteSpaceCount() -> Int {
        prefix { $0 == " " }.count
    }
}
