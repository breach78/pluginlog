import SwiftUI

struct SetupContainerView: View {
  @EnvironmentObject private var appState: AppState
  @State private var isInitializing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Brain Unfog")
        .font(.largeTitle.bold())

      Text("Logseq 그래프 폴더만 선택하세요. 앱 지원 파일은 그래프 안의 숨김 `.buf` 폴더에 자동으로 준비됩니다.")
        .foregroundStyle(.secondary)

      GroupBox("Logseq 그래프 폴더") {
        VStack(alignment: .leading, spacing: 8) {
          if let root = appState.logseqGraphRootURL {
            Label("선택됨", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text(root.path)
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)
          } else {
            Text("프로젝트 페이지가 들어 있는 Logseq graph 루트를 선택해 주세요.")
              .foregroundStyle(.secondary)
          }

          Button(appState.isLogseqGraphConfigured ? "Logseq 그래프 변경" : "Logseq 그래프 선택") {
            chooseLogseqGraph()
          }
          .buttonStyle(.borderedProminent)
          .disabled(isInitializing)

          Text("선택 후 Reminders와 Calendar 권한을 자동으로 한 번 요청합니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Text("별도 저장소, Journal, Compass 설정은 없습니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      if isInitializing {
        HStack(spacing: 10) {
          ProgressView()
          Text("설정 중...")
            .foregroundStyle(.secondary)
        }
      }

      if let errorMessage = appState.errorMessage {
        Text(errorMessage)
          .foregroundStyle(.red)
      }
    }
    .padding(24)
    .frame(minWidth: 620, minHeight: 240)
  }

  private func chooseLogseqGraph() {
    runSetupAction {
      do {
        let urls = try await appState.platformUIFoundation.pathPicker.pick(
          request: PlatformPathPickerRequest(
            kind: .directory,
            message: "Logseq 그래프 루트를 선택해 주세요."
          )
        )
        guard let url = urls.first else { return }
        await appState.configureLogseqGraphRoot(at: url, activateWhenReady: true)
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  private func runSetupAction(_ action: @escaping () async -> Void) {
    isInitializing = true
    Task { @MainActor in
      await action()
      isInitializing = false
    }
  }
}
