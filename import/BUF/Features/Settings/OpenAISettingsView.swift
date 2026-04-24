import SwiftUI

struct OpenAISettingsView: View {
  @EnvironmentObject private var appState: AppState
  @State private var apiKeyDraft: String = ""
  @State private var didJustSaveOpenAI = false

  var body: some View {
    Form {
      Section("OpenAI") {
        Text("Retained 앱에서는 Logseq/Reminders/Calendar 동기화만 기본 범위로 사용합니다. OpenAI 키는 남아 있는 진단/요약 코드가 요구할 때만 사용됩니다.")
          .foregroundStyle(.secondary)

        LabeledContent("키 저장 상태") {
          Text(appState.hasOpenAIAPIKey ? "저장됨" : "없음")
            .foregroundStyle(appState.hasOpenAIAPIKey ? .secondary : .tertiary)
        }

        SecureField("OpenAI API Key", text: $apiKeyDraft)
          .textFieldStyle(.roundedBorder)
          .font(AppInputTypography.font(size: AppInputTypography.defaultPointSize))

        HStack(spacing: 10) {
          Button("저장") {
            let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
              appState.saveOpenAIAPIKey(trimmed)
              apiKeyDraft = ""
              didJustSaveOpenAI = true
            }
          }

          Button("삭제") {
            appState.clearOpenAIAPIKey()
            apiKeyDraft = ""
            didJustSaveOpenAI = false
          }
          .disabled(!appState.hasOpenAIAPIKey)

          Spacer()

          if didJustSaveOpenAI && appState.hasOpenAIAPIKey {
            Text("Keychain에 저장됨")
              .foregroundStyle(.secondary)
          }
        }
      }

      Section("저장소") {
        if let graphRoot = appState.logseqGraphRootURL {
          LabeledContent("Logseq graph") {
            Text(graphRoot.path)
              .textSelection(.enabled)
          }
        }

        if let containerRoot = appState.containerRootURL {
          LabeledContent(".buf") {
            Text(containerRoot.path)
              .textSelection(.enabled)
          }
        }
      }
    }
    .formStyle(.grouped)
    .padding(20)
    .frame(width: 560)
    .onAppear {
      apiKeyDraft = ""
      didJustSaveOpenAI = false
      appState.refreshOpenAIAPIKeyStatus()
    }
  }
}
