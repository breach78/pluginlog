import OSLog

enum AppLogger {
    private static let subsystem = "BUF"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let archive = Logger(subsystem: subsystem, category: "archive")
    static let timeline = Logger(subsystem: subsystem, category: "timeline")
    static let board = Logger(subsystem: subsystem, category: "board")
    static let conflict = Logger(subsystem: subsystem, category: "conflict")
    static let attachment = Logger(subsystem: subsystem, category: "attachment")
    static let notes = Logger(subsystem: subsystem, category: "notes")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
