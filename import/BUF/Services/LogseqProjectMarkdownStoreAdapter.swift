import Foundation

actor LogseqProjectMarkdownStoreAdapter: ProjectMarkdownStore {
  typealias ProjectNoteSnapshot = LogseqProjectPageStore.PageSnapshot

  private let store: LogseqProjectPageStore

  init(store: LogseqProjectPageStore) {
    self.store = store
  }

  func prepareProjectDirectory() async throws {
    try await store.preparePagesDirectory()
  }

  func loadProjectNotesInScope() async throws -> [LogseqProjectPageStore.PageSnapshot] {
    try await store.loadProjectPagesInScope()
  }

  func loadProjectNotesInScope(at fileURLs: [URL]) async throws -> [LogseqProjectPageStore.PageSnapshot] {
    try await store.loadProjectPagesInScope(at: fileURLs)
  }
}
