import Foundation
import SQLite3

/// Product runtime bootstrap seam for the retained sqlite sidecar.
enum RuntimeSidecarSQLiteBootstrap {
    static func ensureInstalled(
        databaseURL: URL,
        fileManager: FileManager = .default,
        ensureWorkspaceRoot: Bool = true
    ) throws {
        let db = try openNormalizedSQLiteConnection(
            at: databaseURL,
            fileManager: fileManager
        )
        defer { sqlite3_close(db) }

        try NormalizedRetainedRuntimeSQLiteSchema.install(in: db)

        if ensureWorkspaceRoot {
            try NormalizedRetainedRuntimeSQLiteSchema.ensureWorkspaceRootExists(in: db)
        }
    }
}
