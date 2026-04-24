import Foundation
import SwiftData

/// Phase 13 cleanup boundary freeze:
/// - `DataStack` is the only app steady-state runtime stack in this file.
/// - Runtime registration is limited to `AttachmentEntity` and `ProjectHistoryEvent`.
/// - Legacy migration/canonical stacks were quarantined to test support in Phase 1.
/// Runtime app stack. Legacy index/sync metadata owners must never be registered here after Phase 12.
/// Phase 13 cleanup boundary keeps only `AttachmentEntity` and `ProjectHistoryEvent` in app steady-state.
struct DataStack {
    let modelContainer: ModelContainer

    init(sqliteURL: URL) throws {
        let configuration = ModelConfiguration(url: sqliteURL)
        modelContainer = try ModelContainer(
            for: AttachmentEntity.self,
            ProjectHistoryEvent.self,
            configurations: configuration
        )
    }
}
