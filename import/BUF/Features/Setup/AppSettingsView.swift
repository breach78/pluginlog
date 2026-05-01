import SwiftUI

struct AppSettingsView: View {
  @EnvironmentObject private var appState: AppState
  @AppStorage(WorkspaceUserDefaultsKey.timelineShowsHiddenProjectLists)
  private var timelineShowsHiddenProjectLists = false
  @State private var isChangingObsidianVault = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("설정")
        .font(.title2.bold())

      GroupBox("Obsidian vault") {
        VStack(alignment: .leading, spacing: 10) {
          Text("`.obsidian` 폴더가 이미 있는 vault 루트를 선택합니다.")
            .foregroundStyle(.secondary)

          SettingsPathRow(title: "현재 vault", value: obsidianVaultPath)
          SettingsPathRow(title: "앱 지원 폴더", value: obsidianBufFolderPath)
          SettingsPathRow(title: "프로젝트 노트", value: obsidianProjectsFolderPath)

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

          Divider()

          VStack(alignment: .leading, spacing: 8) {
            Label("Helper plugin 비활성화됨", systemImage: "pause.circle")
              .foregroundStyle(.secondary)

            Text("Obsidian helper plugin은 설치/업데이트하지 않고, 헬퍼 전용 포커스 링크도 호출하지 않습니다.")
              .font(.footnote)
              .foregroundStyle(.secondary)

            if let status = appState.obsidianHelperPluginInstallStatus {
              SettingsStatusText(
                status,
                isError: status.contains("실패")
              )
            }
          }

          Text("선택 직후 첫 sync는 Reminders -> Obsidian `raw/projects/` 방향입니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GroupBox("Workspace") {
        VStack(alignment: .leading, spacing: 8) {
          Toggle("숨긴 목록 표시", isOn: $timelineShowsHiddenProjectLists)
            .toggleStyle(.switch)

          Text("켜면 타임라인에서 숨김 처리한 목록도 다시 보입니다. 끄면 기존 숨김 목록을 다시 제외합니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

    }
    .padding(24)
    .frame(minWidth: 560, idealWidth: 640, maxWidth: 640, alignment: .leading)
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

private struct SettingsPathRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(title)
        .foregroundStyle(.primary)
        .frame(width: 92, alignment: .leading)

      Text(value)
        .font(.system(.caption, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
      .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
      .help(value)
    }
  }
}

private struct SettingsStatusText: View {
  let text: String
  let isError: Bool

  init(_ text: String, isError: Bool) {
    self.text = text
    self.isError = isError
  }

  var body: some View {
    Text(text)
      .font(.footnote)
      .foregroundStyle(isError ? .red : .secondary)
      .lineLimit(3)
      .truncationMode(.middle)
      .frame(maxWidth: .infinity, alignment: .leading)
      .help(text)
  }
}
