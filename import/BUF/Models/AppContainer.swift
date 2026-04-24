import Foundation

struct AppContainer: Codable, Sendable {
    var rootURL: URL
    var bookmarkData: Data
    var schemaVersion: Int
    var createdAt: Date
}

struct ContainerHealth: Sendable {
    var rootReachable: Bool
    var bookmarkResolved: Bool
    var sqliteReachable: Bool
    var availableBytes: Int64
    var sqliteIntegrityOK: Bool
    var warnings: [String]

    static let unknown = ContainerHealth(
        rootReachable: false,
        bookmarkResolved: false,
        sqliteReachable: false,
        availableBytes: 0,
        sqliteIntegrityOK: false,
        warnings: []
    )
}
