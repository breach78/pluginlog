import SwiftUI

struct SetupContainerView: View {
  @EnvironmentObject private var appState: AppState
  @State private var isInitializing = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Brain Unfog")
        .font(.largeTitle.bold())

      Text("Obsidian vault를 선택하세요. 앱 지원 파일은 vault 안의 숨김 `.buf` 폴더에 준비됩니다.")
        .foregroundStyle(.secondary)

      GroupBox("Obsidian vault") {
        VStack(alignment: .leading, spacing: 8) {
          if let root = appState.obsidianVaultRootURL {
            Label("선택됨", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
            SetupPathText(root.path)
          } else {
            Text("`.obsidian` 폴더가 이미 있는 vault 루트를 선택해 주세요.")
              .foregroundStyle(.secondary)
          }

          Button(appState.isObsidianVaultConfigured ? "Obsidian vault 변경" : "Obsidian vault 선택") {
            runSetupAction {
              await appState.chooseObsidianVaultWithPicker(activateWhenReady: true)
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(isInitializing)

          Text("첫 sync는 Reminders에서 Obsidian `raw/projects/`로 가져오는 방향으로만 실행됩니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Text("`.obsidian`은 새로 만들지 않고, `.buf`, `raw/projects`, helper plugin만 준비합니다.")
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
