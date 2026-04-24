import Foundation

struct ContainerPaths {
    let root: URL

    var manifestURL: URL { root.appendingPathComponent("container.json", conformingTo: .json) }
    var dataDirectory: URL { root.appendingPathComponent("data", conformingTo: .directory) }
    var sqliteURL: URL { dataDirectory.appendingPathComponent("main.sqlite") }
    var notesDirectory: URL { root.appendingPathComponent("notes", conformingTo: .directory) }
    var projectNotesDirectory: URL {
        notesDirectory.appendingPathComponent("projects", conformingTo: .directory)
    }

    var attachmentsDirectory: URL { root.appendingPathComponent("attachments", conformingTo: .directory) }
    var projectAttachmentsDirectory: URL { attachmentsDirectory.appendingPathComponent("projects", conformingTo: .directory) }
    var taskAttachmentsDirectory: URL { attachmentsDirectory.appendingPathComponent("tasks", conformingTo: .directory) }

    var cacheDirectory: URL { root.appendingPathComponent("cache", conformingTo: .directory) }
    var thumbnailsDirectory: URL { cacheDirectory.appendingPathComponent("thumbnails", conformingTo: .directory) }
    var exportsDirectory: URL { root.appendingPathComponent("exports", conformingTo: .directory) }
    var normalizedSQLiteURL: URL { dataDirectory.appendingPathComponent("normalized.sqlite") }

    var archiveAttachmentsDirectory: URL { attachmentsDirectory.appendingPathComponent("archive", conformingTo: .directory) }

    var requiredDirectories: [URL] {
        [
            root,
            dataDirectory,
            notesDirectory,
            projectNotesDirectory,
            attachmentsDirectory,
            projectAttachmentsDirectory,
            taskAttachmentsDirectory,
            cacheDirectory,
            thumbnailsDirectory,
            exportsDirectory,
            archiveAttachmentsDirectory,
        ]
    }
}
