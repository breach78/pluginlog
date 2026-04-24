import SwiftData
import SwiftUI

struct ArchiveView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    private var archivedProjectDescriptors: [WorkspaceProjectDescriptor] {
        ReminderRuntimeProjectionReadModelService.workspaceProjectDescriptors(
            runtimeSnapshot: appState.cachedOutlinerRuntimeProjectionSnapshot,
            context: modelContext
        )
        .filter(\.isArchived)
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Archive")
                    .font(.largeTitle.bold())

                GroupBox("Projects") {
                    VStack(alignment: .leading, spacing: 8) {
                        if !archivedProjectDescriptors.isEmpty {
                            Button("Restore All Projects") {
                                restoreAllProjects()
                            }
                            .buttonStyle(.bordered)
                        }

                        ForEach(archivedProjectDescriptors, id: \.id) { project in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Button("Restore") {
                                    Task { @MainActor in
                                        _ = await appState.restoreProject(project.id, context: modelContext)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .frame(width: 78, alignment: .leading)

                                Text(project.title)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if archivedProjectDescriptors.isEmpty {
                            Text("No archived projects")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
    }

    private func restoreAllProjects() {
        Task { @MainActor in
            for project in archivedProjectDescriptors {
                _ = await appState.restoreProject(project.id, context: modelContext)
            }
        }
    }
}
