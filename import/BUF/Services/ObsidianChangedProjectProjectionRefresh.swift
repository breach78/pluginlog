import Foundation

enum ObsidianChangedProjectProjectionRefresh {
  static func refresh(
    changedFileURLs: [URL],
    store: ObsidianProjectMarkdownStore,
    projectIDs: [UUID],
    calendar: Calendar = .autoupdatingCurrent
  ) async throws -> RetainedWorkspaceSurfaceProjectionLoadResult {
    do {
      let snapshots = try await store.loadProjectNotesInScope(at: uniqueMarkdownFileURLs(changedFileURLs))
      let retainedSnapshot = try ObsidianRetainedProjectionAdapter.build(
        snapshots: snapshots,
        calendar: calendar
      )
      return RetainedWorkspaceSurfaceProjectionBuilder.build(
        snapshot: retainedSnapshot,
        projectIDs: projectIDs,
        calendar: calendar
      )
    } catch let error as RetainedProjectionBuilder.Error {
      return .blocked(.identityFailure(error))
    }
  }

  private static func uniqueMarkdownFileURLs(_ fileURLs: [URL]) -> [URL] {
    var seen: Set<URL> = []
    return fileURLs
      .filter { $0.pathExtension.lowercased() == "md" }
      .map { $0.standardizedFileURL }
      .filter { seen.insert($0).inserted }
      .sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
  }
}
