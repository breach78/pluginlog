import SwiftUI

struct RootSceneView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let modelContainer = appState.modelContainer {
                MainWorkspaceView()
                    .modelContainer(modelContainer)
            } else if appState.isLaunching {
                StartupPlaceholderView()
            } else {
                SetupContainerView()
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        appState.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                appState.errorMessage = nil
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }
}

private struct StartupPlaceholderView: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Brain Unfog")
                .font(.title.bold())

            ProgressView()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
