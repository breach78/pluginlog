import SwiftUI

struct AppSettingsView: View {
  @EnvironmentObject private var appState: AppState
  @State private var isChangingObsidianVault = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("설정")
        .font(.title2.bold())

      GroupBox("Obsidian vault") {
        VStack(alignment: .leading, spacing: 10) {
          Text("`.obsidian` 폴더가 이미 있는 vault 루트를 선택합니다.")
            .foregroundStyle(.secondary)

          LabeledContent("현재 vault") {
            Text(obsidianVaultPath)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }

          LabeledContent("앱 지원 폴더") {
            Text(obsidianBufFolderPath)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }

          LabeledContent("프로젝트 노트") {
            Text(obsidianProjectsFolderPath)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }

          HStack(spacing: 10) {
            Button("Obsidian vault 변경...") {
              chooseObsidianVault()
            }
            .disabled(isChangingObsidianVault)

            if isChangingObsidianVault {
              ProgressView()
                .controlSize(.small)
            }
          }

          Text("선택 직후 첫 sync는 Reminders -> Obsidian `raw/projects/` 방향입니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

    }
    .padding(24)
    .frame(width: 560)
  }

  private var obsidianVaultPath: String {
    appState.obsidianVaultRootURL?.path ?? "선택되지 않음"
  }

  private var obsidianBufFolderPath: String {
    guard let rootURL = appState.obsidianVaultRootURL else { return "선택되지 않음" }
    return rootURL.appendingPathComponent(".buf", isDirectory: true).path
  }

  private var obsidianProjectsFolderPath: String {
    guard let rootURL = appState.obsidianVaultRootURL else { return "선택되지 않음" }
    return rootURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("projects", isDirectory: true)
      .path
  }

  private func chooseObsidianVault() {
    isChangingObsidianVault = true
    Task { @MainActor in
      await appState.chooseObsidianVaultWithPicker(activateWhenReady: true)
      isChangingObsidianVault = false
    }
  }

}
