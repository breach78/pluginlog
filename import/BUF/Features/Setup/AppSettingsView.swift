import SwiftUI

struct AppSettingsView: View {
  @EnvironmentObject private var appState: AppState
  @State private var isChangingGraph = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("설정")
        .font(.title2.bold())

      GroupBox("Logseq 그래프 폴더") {
        VStack(alignment: .leading, spacing: 10) {
          Text("프로젝트 페이지가 들어 있는 Logseq graph 루트를 선택합니다.")
            .foregroundStyle(.secondary)

          LabeledContent("현재 그래프") {
            Text(graphRootPath)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }

          LabeledContent("앱 지원 폴더") {
            Text(bufFolderPath)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }

          HStack(spacing: 10) {
            Button("Logseq 그래프 변경...") {
              chooseLogseqGraph()
            }
            .disabled(isChangingGraph)

            if isChangingGraph {
              ProgressView()
                .controlSize(.small)
            }
          }

          Text("`.buf`는 직접 선택하지 않습니다. 선택한 graph 안에 자동으로 준비됩니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(24)
    .frame(width: 560)
  }

  private var graphRootPath: String {
    appState.logseqGraphRootURL?.path ?? "선택되지 않음"
  }

  private var bufFolderPath: String {
    guard let rootURL = appState.logseqGraphRootURL else { return "선택되지 않음" }
    return rootURL.appendingPathComponent(".buf", isDirectory: true).path
  }

  private func chooseLogseqGraph() {
    isChangingGraph = true
    Task { @MainActor in
      await appState.chooseLogseqGraphRootWithPicker(activateWhenReady: true)
      isChangingGraph = false
    }
  }
}
