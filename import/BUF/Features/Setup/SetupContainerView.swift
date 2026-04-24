@preconcurrency import EventKit
import SwiftUI

struct SetupContainerView: View {
  @EnvironmentObject private var appState: AppState
  @State private var isInitializing = false
  @State private var permissionStatusRefreshToken = UUID()

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Brain Unfog")
        .font(.largeTitle.bold())

      Text("Logseq 그래프 폴더를 선택하면 앱 저장소는 그래프 안의 숨김 폴더 `.buf`에 자동으로 만들어집니다.")
        .foregroundStyle(.secondary)

      GroupBox("1. Logseq 그래프 폴더") {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GroupBox("2. 앱 저장소") {
        VStack(alignment: .leading, spacing: 8) {
          if let root = appState.containerRootURL {
            Label(".buf 저장소 준비됨", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text(root.path)
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)
          } else {
            Text("Logseq 그래프를 선택하면 `.buf` 저장소가 자동으로 준비됩니다.")
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GroupBox("3. 권한") {
        VStack(alignment: .leading, spacing: 8) {
          Text("앱은 Reminders와 Calendar 권한을 한 번 요청하고, 이후 macOS에 저장된 권한 상태를 사용합니다.")
            .foregroundStyle(.secondary)
          Text("권한을 거부해도 앱은 중단되지 않지만, 동기화 기능은 제한됩니다.")
            .foregroundStyle(.secondary)
          permissionStatusRows
          Button("Reminders / Calendar 권한 요청") {
            requestPermissions()
          }
          .disabled(isInitializing)
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
    .frame(minWidth: 680, minHeight: 420)
  }

  private var permissionStatusRows: some View {
    let _ = permissionStatusRefreshToken
    return VStack(alignment: .leading, spacing: 6) {
      permissionStatusRow(
        title: "Reminders",
        status: EKEventStore.authorizationStatus(for: .reminder)
      )
      permissionStatusRow(
        title: "Calendar",
        status: EKEventStore.authorizationStatus(for: .event)
      )
    }
  }

  private func permissionStatusRow(
    title: String,
    status: EKAuthorizationStatus
  ) -> some View {
    Label {
      Text("\(title): \(permissionStatusText(status))")
    } icon: {
      Image(systemName: permissionStatusIconName(status))
        .foregroundStyle(permissionStatusColor(status))
    }
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

  private func requestPermissions() {
    runSetupAction {
      await appState.requestRetainedExternalAccess()
      permissionStatusRefreshToken = UUID()
    }
  }

  private func runSetupAction(_ action: @escaping () async -> Void) {
    isInitializing = true
    Task { @MainActor in
      await action()
      isInitializing = false
    }
  }

  private func permissionStatusText(_ status: EKAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "아직 요청하지 않음"
    case .restricted:
      return "시스템에서 제한됨"
    case .denied:
      return "거부됨"
    case .authorized, .fullAccess:
      return "허용됨"
    case .writeOnly:
      return "쓰기 전용"
    @unknown default:
      return "알 수 없음"
    }
  }

  private func permissionStatusIconName(_ status: EKAuthorizationStatus) -> String {
    switch status {
    case .authorized, .fullAccess:
      return "checkmark.circle.fill"
    case .writeOnly:
      return "exclamationmark.circle.fill"
    case .denied, .restricted:
      return "xmark.circle.fill"
    case .notDetermined:
      return "questionmark.circle.fill"
    @unknown default:
      return "questionmark.circle.fill"
    }
  }

  private func permissionStatusColor(_ status: EKAuthorizationStatus) -> Color {
    switch status {
    case .authorized, .fullAccess:
      return .green
    case .writeOnly:
      return .orange
    case .denied, .restricted:
      return .red
    case .notDetermined:
      return .secondary
    @unknown default:
      return .secondary
    }
  }
}
