import SwiftData
import SwiftUI

private enum PendingCompassAction {
  case adoptPriority(CompassPriorityRecommendation)
  case createMissingTask(CompassMissingTaskSuggestion)
  case applySchedule(CompassScheduleSuggestion)

  var alertTitle: String {
    switch self {
    case .adoptPriority:
      return "오늘 우선순위로 반영"
    case .createMissingTask:
      return "추천 할일 추가"
    case .applySchedule:
      return "오늘 일정에 반영"
    }
  }

  var confirmButtonTitle: String {
    switch self {
    case .adoptPriority:
      return "채택"
    case .createMissingTask:
      return "추가"
    case .applySchedule:
      return "반영"
    }
  }

  var message: String {
    switch self {
    case .adoptPriority(let recommendation):
      return "\"\(recommendation.title)\" 을(를) 오늘 우선순위 작업으로 반영한다."
    case .createMissingTask(let suggestion):
      return "\"\(suggestion.suggestedTaskTitle)\" 를 실제 할일로 추가한다."
    case .applySchedule(let suggestion):
      return "\"\(suggestion.title)\" 제안을 오늘 일정에 반영한다."
    }
  }
}

private enum PendingCompassSystemAction: Hashable {
  case fullRebuild(CompassFullRebuildEstimate)

  var alertTitle: String {
    switch self {
    case .fullRebuild:
      return "전체 재분석"
    }
  }

  var confirmButtonTitle: String {
    switch self {
    case .fullRebuild:
      return "다시 생성"
    }
  }

  var message: String {
    switch self {
    case .fullRebuild(let estimate):
      return """
      저장된 자기모델과 중간 요약을 무시하고 전체 저널을 다시 읽는다.

      로컬 스캔 결과
      - 대상 일수: \(Self.format(estimate.indexedDayCount))일
      - 엔트리 수: \(Self.format(estimate.indexedEntryCount))개
      - 원문 글자 수: 약 \(Self.format(estimate.sourceCharacterCount))자
      - 예상 전송 글자 수: 약 \(Self.format(estimate.estimatedPayloadCharacterCount))자
      - 예상 요청 수: \(Self.format(estimate.estimatedRequestCount))회 (보조 \(Self.format(estimate.supportingRequestCount)) + 메인 \(Self.format(estimate.primaryRequestCount)))
      - 예상 입력 토큰: 약 \(Self.format(estimate.estimatedInputTokenCount))
      - 예상 출력 상한: 약 \(Self.format(estimate.estimatedOutputTokenUpperBound)) 토큰
      - 실행 상한: 요청 \(Self.format(estimate.requestCap))회 / 확인된 토큰 \(Self.format(estimate.knownTokenCap))
      - 모델: \(estimate.supportingModel) + \(estimate.primaryModel)

      위 수치는 로컬 스캔 기반 추정치다. 실제 사용량은 응답 길이와 제공자 과금 기준에 따라 달라질 수 있다.
      """
    }
  }

  private static func format(_ value: Int) -> String {
    value.formatted(.number)
  }
}

@MainActor
private struct CompassServiceFactory {
  let rootURL: URL
  let modelContainer: ModelContainer
  let obsidianRootURL: URL
  let runMonitor: CompassRunMonitor
  let runtimeSnapshotProvider: @MainActor () -> OutlineProjectionRuntimeSnapshot?

  private var journalRootURL: URL {
    Self.compassJournalsRootURL(for: obsidianRootURL)
  }

  private var generator: GeminiCompassService {
    .shared
  }

  private func makeJournalProvider() -> ObsidianCompassJournalProvider {
    let journalRootURL = self.journalRootURL
    return ObsidianCompassJournalProvider(
      rootURL: journalRootURL,
      store: ObsidianJournalStore(rootURL: journalRootURL)
    )
  }

  func makeRuntimeService() -> CompassBoardRuntimeService {
    let journalProvider = makeJournalProvider()
    let workspaceProvider = SwiftDataCompassWorkspaceProvider(
      modelContainer: modelContainer,
      runtimeSnapshotProvider: runtimeSnapshotProvider
    )
    let bootstrapModelStore = CompassModelStore(rootURL: rootURL)
    let recommendationModelStore = CompassModelStore(rootURL: rootURL)
    let bootstrapService = CompassBootstrapService(
      journalProvider: journalProvider,
      modelStore: bootstrapModelStore,
      generator: generator,
      runMonitor: runMonitor
    )
    let deltaUpdateService = CompassDeltaUpdateService(
      journalProvider: journalProvider,
      modelStore: bootstrapModelStore,
      generator: generator,
      runMonitor: runMonitor
    )
    let recommendationService = CompassRecommendationService(
      modelStore: recommendationModelStore,
      generator: generator,
      workspaceProvider: workspaceProvider
    )

    return CompassBoardRuntimeService(
      bootstrapService: bootstrapService,
      deltaUpdateService: deltaUpdateService,
      recommendationService: recommendationService
    )
  }

  func makeRebuildEstimateService() -> CompassRebuildEstimateService {
    CompassRebuildEstimateService(
      journalProvider: makeJournalProvider(),
      generator: generator
    )
  }

  private static func compassJournalsRootURL(for configuredURL: URL) -> URL {
    if isLegacyObsidianProjectsFolder(configuredURL) {
      return configuredURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("journals", isDirectory: true)
    }

    return configuredURL.appendingPathComponent("journals", isDirectory: true)
  }

  private static func isLegacyObsidianProjectsFolder(_ url: URL) -> Bool {
    url.lastPathComponent.caseInsensitiveCompare("projects") == .orderedSame
      && url.deletingLastPathComponent().lastPathComponent.caseInsensitiveCompare("pages")
        == .orderedSame
  }
}

struct CompassBoardScreen: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.modelContext) private var modelContext
  @AppStorage(CompassPreferenceKeys.reanalysisPolicy) private var reanalysisPolicyRawValue =
    CompassReanalysisPolicy.automaticIncremental.rawValue
  @AppStorage(CompassPreferenceKeys.actionPolicy) private var actionPolicyRawValue =
    CompassActionPolicy.approvalRequired.rawValue

  @StateObject private var viewModel = CompassBoardViewModel()
  @StateObject private var runMonitor = CompassRunMonitor()
  @State private var pendingAction: PendingCompassAction?
  @State private var pendingSystemAction: PendingCompassSystemAction?
  @State private var actionMessage: String?
  @State private var isPreparingFullRebuildEstimate = false
  @State private var fullRebuildEstimateTask: Task<Void, Never>?
  @State private var lastFullRebuildEstimate: CompassFullRebuildEstimate?

  private let onRevealProject: ((UUID) -> Void)?

  init(onRevealProject: ((UUID) -> Void)? = nil) {
    self.onRevealProject = onRevealProject
  }

  var body: some View {
    CompassBoardView(
      viewModel: viewModel,
      onAdoptPriority: actionsEnabled
        ? { recommendation in
          pendingAction = .adoptPriority(recommendation)
        }
        : nil,
      onAcceptMissingSuggestion: actionsEnabled
        ? { suggestion in
          pendingAction = .createMissingTask(suggestion)
        }
        : nil,
      onAcceptScheduleSuggestion: actionsEnabled
        ? { suggestion in
          pendingAction = .applySchedule(suggestion)
        }
        : nil
    )
    .safeAreaInset(edge: .top, spacing: 0) {
      if appState.viewMode == .compass {
        topChrome
          .padding(.horizontal, 24)
          .padding(.top, 12)
      }
    }
    .task(id: boardIdentity) {
      lastFullRebuildEstimate = nil
      viewModel.updateRuntime(
        service: runtimeService,
        identity: boardIdentity,
        setupError: setupErrorMessage
      )
      guard appState.viewMode == .compass else { return }
      await viewModel.loadIfNeeded(mode: initialRefreshMode)
    }
    .onChange(of: appState.viewMode) { _, newValue in
      guard newValue == .compass else { return }
      Task { @MainActor in
        await viewModel.loadIfNeeded(mode: initialRefreshMode)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .reminderAppJournalEntriesDidChange)) { _ in
      guard appState.viewMode == .compass else { return }
      guard reanalysisPolicy == .automaticIncremental else {
        showActionMessage("새 저널이 감지됐다. 나침반 갱신을 눌러 변경분을 반영할 수 있다.")
        return
      }
      Task { @MainActor in
        viewModel.reload(mode: .automatic)
      }
    }
    .alert(
      pendingAction?.alertTitle ?? "나침반 반영",
      isPresented: pendingActionBinding,
      presenting: pendingAction
    ) { action in
      Button("취소", role: .cancel) {
        pendingAction = nil
      }
      Button(action.confirmButtonTitle) {
        apply(action)
      }
    } message: { action in
      Text(action.message)
    }
    .alert(
      pendingSystemAction?.alertTitle ?? "나침반 갱신",
      isPresented: pendingSystemActionBinding,
      presenting: pendingSystemAction
    ) { action in
      Button("취소", role: .cancel) {
        pendingSystemAction = nil
      }
      Button(action.confirmButtonTitle) {
        run(action)
      }
    } message: { action in
      Text(action.message)
    }
  }

  private var runtimeService: CompassBoardRuntimeService? {
    guard
      let rootURL = appState.containerRootURL,
      let modelContainer = appState.modelContainer,
      let obsidianRootURL = appState.obsidianProjectsRootURL
    else {
      return nil
    }
    return CompassServiceFactory(
      rootURL: rootURL,
      modelContainer: modelContainer,
      obsidianRootURL: obsidianRootURL,
      runMonitor: runMonitor,
      runtimeSnapshotProvider: { appState.cachedOutlinerRuntimeProjectionSnapshot }
    )
    .makeRuntimeService()
  }

  private var rebuildEstimateService: CompassRebuildEstimateService? {
    guard
      let rootURL = appState.containerRootURL,
      let modelContainer = appState.modelContainer,
      let obsidianRootURL = appState.obsidianProjectsRootURL
    else {
      return nil
    }
    return CompassServiceFactory(
      rootURL: rootURL,
      modelContainer: modelContainer,
      obsidianRootURL: obsidianRootURL,
      runMonitor: runMonitor,
      runtimeSnapshotProvider: { appState.cachedOutlinerRuntimeProjectionSnapshot }
    )
    .makeRebuildEstimateService()
  }

  private var pendingActionBinding: Binding<Bool> {
    Binding(
      get: { pendingAction != nil },
      set: { isPresented in
        if !isPresented {
          pendingAction = nil
        }
      }
    )
  }

  private var pendingSystemActionBinding: Binding<Bool> {
    Binding(
      get: { pendingSystemAction != nil },
      set: { isPresented in
        if !isPresented {
          pendingSystemAction = nil
        }
      }
    )
  }

  private var boardIdentity: String {
    [
      appState.containerRootURL?.path ?? "missing-root",
      appState.obsidianProjectsRootURL?.path ?? "missing-obsidian",
      appState.modelContainer == nil ? "container-missing" : "container-ready",
      reanalysisPolicy.rawValue,
      actionPolicy.rawValue,
    ]
    .joined(separator: "|")
  }

  private var setupErrorMessage: String? {
    if appState.containerRootURL == nil {
      return "앱 컨테이너가 아직 준비되지 않았다."
    }
    if appState.obsidianProjectsRootURL == nil {
      return "옵시디언 폴더를 먼저 연결해야 한다."
    }
    if appState.modelContainer == nil {
      return "작업 데이터 스택이 아직 준비되지 않았다."
    }
    return nil
  }

  private var topChrome: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 10) {
        if isBusy {
          ProgressView()
            .controlSize(.small)
        }

        Text(statusLine)
          .font(.custom("SansMonoCJKFinalDraft", size: 12))
          .foregroundStyle(Color(red: 0.20, green: 0.16, blue: 0.14))
          .lineLimit(2)

        Spacer(minLength: 12)

        Button(viewModel.snapshot == nil ? "초기 생성" : "갱신") {
          viewModel.reload(mode: .manual)
        }
        .buttonStyle(.plain)
        .font(.custom("SansMonoCJKFinalDraft-Bold", size: 12))
        .foregroundStyle(canRunSystemActions ? Color.white : .secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
              canRunSystemActions
                ? Color(red: 0.27, green: 0.38, blue: 0.63)
                : Color.black.opacity(0.06)
            )
        )
        .disabled(!canRunSystemActions)

        if isBusy {
          Button("중단") {
            cancelCurrentOperation()
          }
          .buttonStyle(.plain)
          .font(.custom("SansMonoCJKFinalDraft-Bold", size: 12))
          .foregroundStyle(Color.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(Color(red: 0.63, green: 0.18, blue: 0.18))
          )
        }

        Button(isPreparingFullRebuildEstimate ? "스캔 중..." : "전체 재분석") {
          prepareFullRebuildConfirmation()
        }
        .buttonStyle(.plain)
        .font(.custom("SansMonoCJKFinalDraft-Bold", size: 12))
        .foregroundStyle(canRunSystemActions ? Color.white : .secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
              canRunSystemActions
                ? Color(red: 0.70, green: 0.39, blue: 0.18)
                : Color.black.opacity(0.06)
            )
        )
        .disabled(!canRunSystemActions)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .overlaySurface(
        cornerRadius: 12,
        fillColor: Color.white.opacity(0.95),
        strokeColor: Color(red: 0.49, green: 0.33, blue: 0.23),
        style: .lightweight()
      )

      if let actionMessage {
        actionBanner(actionMessage)
      }

      if let safetyLine {
        actionBanner(safetyLine, systemImage: "gauge.with.dots.needle.50percent")
      }
    }
  }

  private var statusLine: String {
    if isPreparingFullRebuildEstimate {
      return "전체 재분석 범위를 로컬로 스캔 중이다. 아직 API 요청은 보내지 않는다."
    }
    if let statusMessage = viewModel.statusMessage, !statusMessage.isEmpty {
      return statusMessage
    }
    if let setupErrorMessage {
      return setupErrorMessage
    }
    if actionPolicy == .recommendationOnly {
      return "추천만 보기 정책이 켜져 있어 실제 할일과 일정 반영은 비활성화된다."
    }
    if reanalysisPolicy == .manualRefreshOnly {
      return "수동 갱신 정책이다. 저장된 자기모델만 읽고, 갱신 버튼으로만 변경분을 반영한다."
    }
    let safeguards = CompassGenerationSafeguards.default
    return "처음에는 상단의 초기 생성으로 1회 자기모델을 만들고, 이후에는 변경된 저널만 반영한다. 초기 생성 상한은 최대 \(safeguards.bootstrapMaxLLMRequests)회 / \(safeguards.bootstrapMaxKnownTokens) 토큰이다."
  }

  private var canRunSystemActions: Bool {
    runtimeService != nil && rebuildEstimateService != nil && !isBusy
  }

  private var isBusy: Bool {
    viewModel.isLoading || isPreparingFullRebuildEstimate
  }

  private var safetyLine: String? {
    if runMonitor.isRunning, let progress = runMonitor.progress, let estimate = runMonitor.estimate {
      return "\(progress.phase.title) 진행 중 · 요청 \(progress.attemptedRequestCount)/\(estimate.requestCap) · 확인된 토큰 \(progress.knownTotalTokens)/\(estimate.knownTokenCap) · 예상 출력 상한 \(estimate.estimatedOutputTokenUpperBound)"
    }

    if let lastFullRebuildEstimate, !isPreparingFullRebuildEstimate {
      return "최근 전체 재분석 추정 · 원문 약 \(lastFullRebuildEstimate.sourceCharacterCount.formatted(.number))자 · 입력 약 \(lastFullRebuildEstimate.estimatedInputTokenCount.formatted(.number)) 토큰 · 요청 \(lastFullRebuildEstimate.estimatedRequestCount.formatted(.number))/\(lastFullRebuildEstimate.requestCap.formatted(.number))회"
    }

    if let lastMessage = runMonitor.lastMessage, !lastMessage.isEmpty {
      return lastMessage
    }

    return nil
  }

  private var actionsEnabled: Bool {
    actionPolicy == .approvalRequired
  }

  private var reanalysisPolicy: CompassReanalysisPolicy {
    CompassReanalysisPolicy(rawValue: reanalysisPolicyRawValue) ?? .automaticIncremental
  }

  private var actionPolicy: CompassActionPolicy {
    CompassActionPolicy(rawValue: actionPolicyRawValue) ?? .approvalRequired
  }

  private var initialRefreshMode: CompassBoardRefreshMode {
    switch reanalysisPolicy {
    case .automaticIncremental:
      return .automatic
    case .manualRefreshOnly:
      return .storedModelOnly
    }
  }

  private func apply(_ action: PendingCompassAction) {
    pendingAction = nil
    let service = CompassActionService(appState: appState, context: modelContext)

    Task { @MainActor in
      do {
        switch action {
        case .adoptPriority(let recommendation):
          let result = try await service.adoptPriority(recommendation)
          if let projectID = result.projectID {
            onRevealProject?(projectID)
          }
          showActionMessage("오늘 우선순위로 반영했다.")
        case .createMissingTask(let suggestion):
          let result = try await service.createMissingTask(from: suggestion)
          onRevealProject?(result.projectID)
          showActionMessage("추천된 할일을 추가했다.")
        case .applySchedule(let suggestion):
          let result = try await service.applyScheduleSuggestion(suggestion)
          if let projectID = result.projectIDs.first {
            onRevealProject?(projectID)
          }
          showActionMessage("오늘 일정에 반영했다.")
        }
        viewModel.reload(mode: .manual)
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  private func run(_ action: PendingCompassSystemAction) {
    pendingSystemAction = nil

    Task { @MainActor in
      do {
        switch action {
        case .fullRebuild(let estimate):
          lastFullRebuildEstimate = estimate
          viewModel.reload(mode: .fullRebuild)
          if viewModel.errorMessage == nil {
            showActionMessage("전체 재분석으로 자기모델을 다시 만들었다.")
          }
        }
      }
    }
  }

  private func prepareFullRebuildConfirmation() {
    guard let rebuildEstimateService else { return }

    fullRebuildEstimateTask?.cancel()
    isPreparingFullRebuildEstimate = true
    actionMessage = nil

    fullRebuildEstimateTask = Task { @MainActor in
      defer {
        isPreparingFullRebuildEstimate = false
        fullRebuildEstimateTask = nil
      }

      do {
        let estimate = try await rebuildEstimateService.estimateFullRebuild()
        try Task.checkCancellation()
        lastFullRebuildEstimate = estimate
        pendingSystemAction = .fullRebuild(estimate)
      } catch is CancellationError {
        showActionMessage("전체 재분석 예상 계산을 중단했다.")
      } catch {
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  private func cancelCurrentOperation() {
    if isPreparingFullRebuildEstimate {
      fullRebuildEstimateTask?.cancel()
      return
    }

    viewModel.cancelCurrentRun()
    runMonitor.cancel()
  }

  private func showActionMessage(_ message: String) {
    actionMessage = message

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      guard actionMessage == message else { return }
      actionMessage = nil
    }
  }

  private func actionBanner(_ text: String, systemImage: String = "checkmark.circle.fill") -> some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(Color(red: 0.19, green: 0.42, blue: 0.31))
      Text(text)
        .font(.custom("SansMonoCJKFinalDraft-Bold", size: 12))
        .foregroundStyle(Color(red: 0.20, green: 0.16, blue: 0.14))
      Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .overlaySurface(
      cornerRadius: 12,
      fillColor: Color.white.opacity(0.95),
      strokeColor: Color(red: 0.49, green: 0.33, blue: 0.23),
      style: .lightweight()
    )
  }

}

#Preview {
  CompassBoardScreen()
    .environmentObject(AppState())
}
