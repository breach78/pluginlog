import SwiftUI

struct AppSettingsView: View {
  @EnvironmentObject private var appState: AppState
  @AppStorage(WorkspaceUserDefaultsKey.timelineShowsHiddenProjectLists)
  private var timelineShowsHiddenProjectLists = false
  @AppStorage(ScheduleUserDefaultsKey.dateBoundarySnappingEnabled)
  private var isScheduleDateBoundarySnappingEnabled = true
  @State private var isChangingObsidianVault = false
  @State private var performanceReport = SyncPerformanceCounter.diagnosticReport()

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("설정")
        .font(.title2.bold())

      GroupBox("Vault") {
        VStack(alignment: .leading, spacing: 10) {
          Text("앱 지원 저장소와 저널/첨부 파일을 둘 vault 루트를 선택합니다.")
            .foregroundStyle(.secondary)

          SettingsPathRow(title: "현재 vault", value: obsidianVaultPath)
          SettingsPathRow(title: "앱 지원 폴더", value: obsidianBufFolderPath)
          SettingsPathRow(title: "저널 폴더", value: journalFolderPath)

          HStack(spacing: 10) {
            Button("Vault 변경...") {
              chooseObsidianVault()
            }
            .disabled(isChangingObsidianVault)

            if isChangingObsidianVault {
              ProgressView()
                .controlSize(.small)
            }
          }

          Text("프로젝트와 할일 상태는 앱 지원 저장소가 사용하며, Obsidian 프로젝트 마크다운은 읽거나 쓰지 않습니다.")
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

      GroupBox("Schedule") {
        VStack(alignment: .leading, spacing: 8) {
          Toggle("날짜 경계 스냅", isOn: $isScheduleDateBoundarySnappingEnabled)
            .toggleStyle(.switch)

          Text("켜면 스케줄 보드를 가로로 스크롤한 뒤 가장 가까운 날짜 경계에 맞춥니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

#if DEBUG
      GroupBox("Diagnostics") {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 10) {
            Button("성능 계측 새로고침") {
              performanceReport = SyncPerformanceCounter.diagnosticReport()
            }

            Button("성능 계측 초기화") {
              SyncPerformanceCounter.reset()
              performanceReport = SyncPerformanceCounter.diagnosticReport()
            }
          }

          Text(performanceReport)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
#endif

    }
    .padding(24)
    .frame(minWidth: 560, idealWidth: 640, maxWidth: 640, alignment: .leading)
    .onAppear {
      performanceReport = SyncPerformanceCounter.diagnosticReport()
    }
  }

  private var obsidianVaultPath: String {
    appState.obsidianVaultRootURL?.path ?? "선택되지 않음"
  }

  private var obsidianBufFolderPath: String {
    guard let rootURL = appState.obsidianVaultRootURL else { return "선택되지 않음" }
    return rootURL.appendingPathComponent(".buf", isDirectory: true).path
  }

  private var journalFolderPath: String {
    guard let rootURL = appState.obsidianVaultRootURL else { return "선택되지 않음" }
    return rootURL
      .appendingPathComponent("raw", isDirectory: true)
      .appendingPathComponent("journals", isDirectory: true)
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
