import Foundation

struct ContainerPaths {
    let root: URL

    var manifestURL: URL { root.appendingPathComponent("container.json", conformingTo: .json) }
    var dataDirectory: URL { root.appendingPathComponent("data", conformingTo: .directory) }
    var sqliteURL: URL { dataDirectory.appendingPathComponent("main.sqlite") }
    var normalizedSQLiteURL: URL { dataDirectory.appendingPathComponent("normalized.sqlite") }

    var requiredDirectories: [URL] {
        [
            root,
            dataDirectory,
        ]
    }
}
