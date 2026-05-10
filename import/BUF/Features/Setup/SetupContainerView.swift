import SwiftUI

struct SetupContainerView: View {
  @EnvironmentObject private var appState: AppState
  @State private var isInitializing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Brain Unfog")
        .font(.largeTitle.bold())

      Text("Vault를 선택하세요. 앱 지원 파일은 vault 안의 숨김 `.buf` 폴더에 준비됩니다.")
        .foregroundStyle(.secondary)

      GroupBox("Vault") {
        VStack(alignment: .leading, spacing: 8) {
          if let root = appState.obsidianVaultRootURL {
            Label("선택됨", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
            SetupPathText(root.path)
          } else {
            Text("`.obsidian` 폴더가 이미 있는 vault 루트를 선택해 주세요.")
              .foregroundStyle(.secondary)
          }

          Button(appState.isObsidianVaultConfigured ? "Vault 변경" : "Vault 선택") {
            runSetupAction {
              await appState.chooseObsidianVaultWithPicker(activateWhenReady: true)
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(isInitializing)

          Text("프로젝트와 할일 상태는 앱 지원 저장소에 보관하고, 저널은 `raw/journals`에 저장합니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Text("`.obsidian`은 새로 만들지 않고, `.buf`와 `raw/journals`만 준비합니다.")
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

  private func runSetupAction(_ action: @escaping () async -> Void) {
    isInitializing = true
    Task { @MainActor in
      await action()
      isInitializing = false
    }
  }
}

private struct SetupPathText: View {
  let path: String

  init(_ path: String) {
    self.path = path
  }

  var body: some View {
    Text(path)
      .font(.system(.body, design: .monospaced))
      .lineLimit(1)
      .truncationMode(.middle)
      .textSelection(.enabled)
    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
    .help(path)
  }
}
