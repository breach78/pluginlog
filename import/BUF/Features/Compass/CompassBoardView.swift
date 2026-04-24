import SwiftUI

@MainActor
final class CompassBoardViewModel: ObservableObject {
  @Published private(set) var snapshot: CompassBoardSnapshot?
  @Published private(set) var isLoading = false
  @Published private(set) var statusMessage: String?
  @Published private(set) var errorMessage: String?

  private var service: (any CompassBoardRuntimeServing)?
  private var serviceIdentity = "unconfigured"
  private var hasLoaded = false
  private var currentTask: Task<Void, Never>?

  init(
    initialSnapshot: CompassBoardSnapshot? = nil
  ) {
    self.snapshot = initialSnapshot
    self.hasLoaded = initialSnapshot != nil
  }

  func updateRuntime(
    service: (any CompassBoardRuntimeServing)?,
    identity: String,
    setupError: String? = nil
  ) {
    let didChange = serviceIdentity != identity
    self.serviceIdentity = identity
    self.service = service

    if didChange {
      currentTask?.cancel()
      snapshot = nil
      hasLoaded = false
      statusMessage = nil
      if service != nil {
        errorMessage = nil
      }
    }

    if service == nil {
      errorMessage = setupError ?? "나침반 서비스가 아직 연결되지 않았다."
    }
  }

  func loadIfNeeded(mode: CompassBoardRefreshMode = .automatic) async {
    guard !hasLoaded else { return }
    reload(mode: mode)
  }

  func reload(mode: CompassBoardRefreshMode = .manual) {
    guard !isLoading else { return }
    guard service != nil else { return }
    currentTask?.cancel()
    currentTask = Task { [weak self] in
      await self?.performReload(mode: mode)
    }
  }

  func cancelCurrentRun() {
    currentTask?.cancel()
    currentTask = nil
    isLoading = false
    statusMessage = "나침반 실행을 중단했다."
    errorMessage = nil
    hasLoaded = true
  }

  private func performReload(mode: CompassBoardRefreshMode) async {
    guard let service else { return }
    isLoading = true
    if snapshot == nil {
      errorMessage = nil
    }

    defer {
      isLoading = false
      currentTask = nil
    }

    do {
      let result = try await service.loadSnapshot(referenceDate: .now, mode: mode)
      try Task.checkCancellation()
      snapshot = result.snapshot
      statusMessage = result.statusMessage
      hasLoaded = true
      errorMessage = nil
    } catch is CancellationError {
      statusMessage = "나침반 실행을 중단했다."
      errorMessage = nil
      hasLoaded = true
    } catch let error as CompassBoardRuntimeServiceError {
      statusMessage = error.localizedDescription
      errorMessage = error.localizedDescription
      hasLoaded = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct CompassBoardView: View {
  @ObservedObject var viewModel: CompassBoardViewModel
  private let onAdoptPriority: ((CompassPriorityRecommendation) -> Void)?
  private let onAcceptMissingSuggestion: ((CompassMissingTaskSuggestion) -> Void)?
  private let onAcceptScheduleSuggestion: ((CompassScheduleSuggestion) -> Void)?

  init(
    viewModel: CompassBoardViewModel,
    onAdoptPriority: ((CompassPriorityRecommendation) -> Void)? = nil,
    onAcceptMissingSuggestion: ((CompassMissingTaskSuggestion) -> Void)? = nil,
    onAcceptScheduleSuggestion: ((CompassScheduleSuggestion) -> Void)? = nil
  ) {
    self.viewModel = viewModel
    self.onAdoptPriority = onAdoptPriority
    self.onAcceptMissingSuggestion = onAcceptMissingSuggestion
    self.onAcceptScheduleSuggestion = onAcceptScheduleSuggestion
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if let snapshot = viewModel.snapshot {
          heroSection(snapshot.northStar, generatedAt: snapshot.generatedAt)
          prioritySection(snapshot.priorities)
          missingSection(snapshot.missingSuggestions)
          scheduleSection(snapshot.scheduleSuggestions)
          evidenceSection(
            overview: snapshot.selfModelOverview,
            analysisStatus: snapshot.analysisStatus,
            patterns: snapshot.patternInsights,
            evidence: snapshot.evidenceHighlights
          )
        } else if viewModel.isLoading {
          loadingSection
        } else {
          emptyState
        }
      }
      .padding(24)
      .frame(maxWidth: 1120, alignment: .leading)
    }
    .background(compassBackground.ignoresSafeArea())
  }

  private var compassBackground: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.97, green: 0.95, blue: 0.90),
          Color(red: 0.93, green: 0.90, blue: 0.83),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      VStack {
        HStack {
          Circle()
            .fill(Color(red: 0.83, green: 0.43, blue: 0.20).opacity(0.12))
            .frame(width: 280, height: 280)
            .blur(radius: 18)
          Spacer()
        }
        Spacer()
      }
      .padding(-40)
    }
  }

  private func heroSection(_ northStar: CompassNorthStar, generatedAt: Date) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Text("TODAY'S COMPASS")
            .font(compassFont(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 0.54, green: 0.27, blue: 0.14))
          Text(northStar.title)
            .font(compassFont(size: 30, weight: .bold))
            .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.11))
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Text(compassTimestamp(generatedAt))
          .font(compassFont(size: 12))
          .foregroundStyle(.secondary)
      }

      Text(northStar.summary)
        .font(compassFont(size: 16))
        .foregroundStyle(Color(red: 0.23, green: 0.20, blue: 0.18))
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
        capsule(label: "WORK MODE", value: northStar.workMode)
        if let caution = northStar.caution, !caution.isEmpty {
          capsule(label: "CAUTION", value: caution)
        }
      }
    }
    .padding(22)
    .overlaySurface(
      cornerRadius: 20,
      fillColor: Color(red: 0.99, green: 0.98, blue: 0.95),
      strokeColor: Color(red: 0.49, green: 0.33, blue: 0.23),
      style: .card()
    )
  }

  private func prioritySection(_ priorities: [CompassPriorityRecommendation]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: "오늘 반드시 전진할 3개", subtitle: "현재 작업 후보 중 오늘 밀어야 할 것")

      if priorities.isEmpty {
        mutedNote("현재 추천 가능한 작업 후보가 아직 없다.")
      } else {
        ForEach(priorities) { priority in
          VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 4) {
              Text(priority.title)
                  .font(compassFont(size: 18, weight: .semibold))
                  .foregroundStyle(Color(red: 0.15, green: 0.13, blue: 0.11))
                if let projectTitle = priority.projectTitle {
                  Text(projectTitle)
                    .font(compassFont(size: 12))
                    .foregroundStyle(Color(red: 0.54, green: 0.27, blue: 0.14))
                }
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 4) {
                if let dueDate = priority.dueDate {
                  Text(compassDayLabel(dueDate))
                    .font(compassFont(size: 12, weight: .semibold))
                    .foregroundStyle(priority.isOverdue ? Color.red : .secondary)
                }
                if let estimatedMinutes = priority.estimatedMinutes {
                  Text("\(estimatedMinutes) min")
                    .font(compassFont(size: 12))
                    .foregroundStyle(.secondary)
                }
              }
            }

            Text(priority.rationale)
              .font(compassFont(size: 14))
              .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))

            evidenceStrip(priority.evidence)

            Button(action: {
              onAdoptPriority?(priority)
            }) {
              Text(onAdoptPriority == nil ? "반영 비활성" : "오늘 우선순위로 채택")
                .font(compassFont(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(onAdoptPriority == nil ? .secondary : Color.white)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                  onAdoptPriority == nil
                    ? Color.black.opacity(0.06)
                    : Color(red: 0.19, green: 0.42, blue: 0.31)
                )
            )
            .disabled(onAdoptPriority == nil)
          }
          .padding(18)
          .overlaySurface(
            cornerRadius: 16,
            fillColor: .white,
            strokeColor: Color(red: 0.49, green: 0.33, blue: 0.23),
            style: .lightweight()
          )
        }
      }
    }
  }

  private func missingSection(_ suggestions: [CompassMissingTaskSuggestion]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: "빠진 일 / 추가 제안", subtitle: "저널 패턴상 시스템에 아직 없는 작업")

      if suggestions.isEmpty {
        mutedNote("새로 추가할 만한 빠진 일은 아직 감지되지 않았다.")
      } else {
        ForEach(suggestions) { suggestion in
          HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
              Text(suggestion.title)
                .font(compassFont(size: 17, weight: .semibold))
              Text(suggestion.suggestedTaskTitle)
                .font(compassFont(size: 14, weight: .regular))
                .foregroundStyle(Color(red: 0.54, green: 0.27, blue: 0.14))
              Text(suggestion.rationale)
                .font(compassFont(size: 14))
                .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
              evidenceStrip(suggestion.evidence)
            }
            Spacer()
            Button(action: {
              onAcceptMissingSuggestion?(suggestion)
            }) {
              Text(onAcceptMissingSuggestion == nil ? "반영 비활성" : "할일 제안으로 채택")
                .font(compassFont(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(onAcceptMissingSuggestion == nil ? .secondary : Color.white)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                  onAcceptMissingSuggestion == nil
                    ? Color.black.opacity(0.06)
                    : Color(red: 0.70, green: 0.39, blue: 0.18)
                )
            )
            .disabled(onAcceptMissingSuggestion == nil)
          }
          .padding(18)
          .overlaySurface(
            cornerRadius: 16,
            fillColor: .white,
            strokeColor: Color(red: 0.49, green: 0.33, blue: 0.23),
            style: .lightweight()
          )
        }
      }
    }
  }

  private func scheduleSection(_ suggestions: [CompassScheduleSuggestion]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: "오늘의 시간 배치", subtitle: "추천된 작업을 하루 안에 놓는 방식")

      if suggestions.isEmpty {
        mutedNote("시간 배치 제안은 아직 준비되지 않았다.")
      } else {
        ForEach(suggestions) { suggestion in
          HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
              Text(suggestion.title)
                .font(compassFont(size: 17, weight: .semibold))
              Text(suggestion.summary)
                .font(compassFont(size: 14))
                .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
              Text(compassTimeLabel(suggestion))
                .font(compassFont(size: 13, weight: .semibold))
              Text("\(suggestion.durationMinutes) min")
                .font(compassFont(size: 12))
                .foregroundStyle(.secondary)
            }
            Button(action: {
              onAcceptScheduleSuggestion?(suggestion)
            }) {
              Text(onAcceptScheduleSuggestion == nil ? "반영 비활성" : "오늘 일정으로 제안")
                .font(compassFont(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(onAcceptScheduleSuggestion == nil ? .secondary : Color.white)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                  onAcceptScheduleSuggestion == nil
                    ? Color.black.opacity(0.06)
                    : Color(red: 0.27, green: 0.38, blue: 0.63)
                )
            )
            .disabled(onAcceptScheduleSuggestion == nil)
          }
          .padding(18)
          .overlaySurface(
            cornerRadius: 16,
            fillColor: .white,
            strokeColor: Color(red: 0.49, green: 0.33, blue: 0.23),
            style: .lightweight()
          )
        }
      }
    }
  }

  private func evidenceSection(
    overview: String,
    analysisStatus: CompassAnalysisStatus?,
    patterns: [CompassPatternInsight],
    evidence: [CompassEvidencePointer]
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(title: "근거와 패턴", subtitle: "추천이 나온 배경과 현재 자기모델")

      VStack(alignment: .leading, spacing: 10) {
        Text("SELF MODEL")
          .font(compassFont(size: 12, weight: .semibold))
          .foregroundStyle(Color(red: 0.54, green: 0.27, blue: 0.14))
        Text(overview)
          .font(compassFont(size: 15))
          .foregroundStyle(Color(red: 0.23, green: 0.20, blue: 0.18))
      }
      .padding(18)
      .overlaySurface(
        cornerRadius: 16,
        fillColor: Color(red: 0.99, green: 0.98, blue: 0.95),
        strokeColor: Color(red: 0.49, green: 0.33, blue: 0.23),
        style: .lightweight()
      )

      if let analysisStatus {
        analysisStatusCard(analysisStatus)
      }

      ForEach(patterns) { pattern in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(pattern.title)
              .font(compassFont(size: 16, weight: .semibold))
            Spacer()
            Text(pattern.confidence.rawValue.uppercased())
              .font(compassFont(size: 11, weight: .semibold))
              .foregroundStyle(Color(red: 0.54, green: 0.27, blue: 0.14))
          }
          Text(pattern.summary)
            .font(compassFont(size: 14))
            .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
        }
        .padding(18)
        .overlaySurface(
          cornerRadius: 16,
          fillColor: .white,
          strokeColor: Color(red: 0.49, green: 0.33, blue: 0.23),
          style: .lightweight()
        )
      }

      if !evidence.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Text("EVIDENCE")
            .font(compassFont(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 0.54, green: 0.27, blue: 0.14))
          ForEach(evidence) { pointer in
            VStack(alignment: .leading, spacing: 4) {
              Text(pointer.dayKey ?? pointer.sourceID)
                .font(compassFont(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
              if let excerpt = pointer.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                  .font(compassFont(size: 13))
                  .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
              }
            }
          }
        }
        .padding(18)
        .overlaySurface(
          cornerRadius: 16,
          fillColor: .white,
          strokeColor: Color(red: 0.49, green: 0.33, blue: 0.23),
          style: .lightweight()
        )
      }
    }
  }

  private func analysisStatusCard(_ status: CompassAnalysisStatus) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("SYSTEM")
        .font(compassFont(size: 12, weight: .semibold))
        .foregroundStyle(Color(red: 0.54, green: 0.27, blue: 0.14))

      Text(status.rebuildPolicySummary)
        .font(compassFont(size: 14))
        .foregroundStyle(Color(red: 0.23, green: 0.20, blue: 0.18))

      HStack(spacing: 10) {
        capsule(label: "SCHEMA", value: "v\(status.schemaVersion)")
        capsule(
          label: "PROMPTS",
          value:
            "B\(status.promptVersions.bootstrapPromptVersion) · D\(status.promptVersions.deltaPromptVersion) · R\(status.promptVersions.recommendationPromptVersion)"
        )
      }

      HStack(spacing: 10) {
        capsule(label: "MODELS", value: status.activeModelConfiguration.primaryModel)
        capsule(label: "SUPPORT", value: status.activeModelConfiguration.supportingModel)
      }

      if let seedManifest = status.seedManifest {
        HStack(spacing: 10) {
          capsule(label: "SEED", value: seedManifest.status.title)
          capsule(label: "ORIGIN", value: seedManifest.origin.title)
          if status.hasSeedReview {
            capsule(label: "REVIEW", value: "available")
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("BASELINE")
            .font(compassFont(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
          Text("approved: \(optionalTimestamp(seedManifest.approvedAt))")
            .font(compassFont(size: 12))
            .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
          Text("imported: \(optionalTimestamp(seedManifest.importedAt))")
            .font(compassFont(size: 12))
            .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
          Text(
            "window: \(seedManifest.journalWindow.indexedDayCount)d · \(seedManifest.journalWindow.indexedEntryCount)e"
          )
          .font(compassFont(size: 12))
          .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("LAST RUNS")
          .font(compassFont(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
        Text("full: \(optionalTimestamp(status.lastFullAnalysisAt))")
          .font(compassFont(size: 12))
          .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
        Text("delta: \(optionalTimestamp(status.lastIncrementalUpdateAt))")
          .font(compassFont(size: 12))
          .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("TOKEN LEDGER")
          .font(compassFont(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
        Text(
          "total \(status.totalUsage.totalTokenCount) · bootstrap \(status.usageLedger.bootstrap.totalTokenCount) · delta \(status.usageLedger.delta.totalTokenCount) · rec \(status.usageLedger.recommendation.totalTokenCount)"
        )
        .font(compassFont(size: 12))
        .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("FULL REBUILD CONDITIONS")
          .font(compassFont(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
        Text(status.allowedRebuildReasons.map(\.title).joined(separator: " · "))
          .font(compassFont(size: 12))
          .foregroundStyle(Color(red: 0.26, green: 0.23, blue: 0.20))
      }

      if let lastBlockedReason = status.lastBlockedRebuildReason, !lastBlockedReason.isEmpty {
        Text("last blocked: \(lastBlockedReason)")
          .font(compassFont(size: 12))
          .foregroundStyle(Color(red: 0.70, green: 0.30, blue: 0.18))
      }
    }
    .padding(18)
    .overlaySurface(
      cornerRadius: 16,
      fillColor: .white,
      strokeColor: Color(red: 0.49, green: 0.33, blue: 0.23),
      style: .lightweight()
    )
  }

  private var loadingSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      ProgressView()
        .controlSize(.large)
      Text("나침반을 계산하는 중이다.")
        .font(compassFont(size: 16, weight: .semibold))
      Text("저널 자기모델, 최근 델타, 현재 작업 후보를 합쳐 오늘의 방향을 정리한다.")
        .font(compassFont(size: 14))
        .foregroundStyle(.secondary)
    }
    .padding(24)
    .overlaySurface(
      cornerRadius: 18,
      fillColor: Color.white,
      strokeColor: .secondary,
      style: .card()
    )
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("나침반 화면 준비 중")
        .font(compassFont(size: 22, weight: .bold))
      if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
        Text(errorMessage)
          .font(compassFont(size: 14))
          .foregroundStyle(Color.red)
      } else {
        Text("자기모델이 아직 없거나, 이 보드에 연결된 서비스가 없다.")
          .font(compassFont(size: 14))
          .foregroundStyle(.secondary)
      }
    }
    .padding(24)
    .overlaySurface(
      cornerRadius: 18,
      fillColor: Color.white,
      strokeColor: .secondary,
      style: .card()
    )
  }

  private func sectionHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(compassFont(size: 24, weight: .bold))
        .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.11))
      Text(subtitle)
        .font(compassFont(size: 13))
        .foregroundStyle(.secondary)
    }
  }

  private func mutedNote(_ text: String) -> some View {
    Text(text)
      .font(compassFont(size: 14))
      .foregroundStyle(.secondary)
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlaySurface(
        cornerRadius: 16,
        fillColor: Color.white.opacity(0.92),
        strokeColor: .secondary,
        style: .lightweight()
      )
  }

  private func capsule(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(compassFont(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(compassFont(size: 12, weight: .semibold))
        .foregroundStyle(Color(red: 0.22, green: 0.17, blue: 0.14))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.black.opacity(0.045))
    )
  }

  private func evidenceStrip(_ evidence: [CompassEvidencePointer]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(evidence.prefix(3)) { pointer in
          Text(pointer.excerpt ?? pointer.dayKey ?? pointer.sourceID)
            .font(compassFont(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
              RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(Color.black.opacity(0.05))
            )
        }
      }
    }
  }

  private func compassTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy.MM.dd HH:mm"
    return formatter.string(from: date)
  }

  private func optionalTimestamp(_ date: Date?) -> String {
    guard let date else { return "-" }
    return compassTimestamp(date)
  }

  private func compassDayLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ko_KR")
    formatter.dateFormat = "M/d"
    return formatter.string(from: date)
  }

  private func compassTimeLabel(_ suggestion: CompassScheduleSuggestion) -> String {
    guard let startHour = suggestion.startHour, let startMinute = suggestion.startMinute else {
      return "Flexible"
    }
    return String(format: "%02d:%02d", startHour, startMinute)
  }

  private func compassFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    let name: String
    switch weight {
    case .bold, .semibold, .heavy, .black:
      name = "SansMonoCJKFinalDraft-Bold"
    default:
      name = "SansMonoCJKFinalDraft"
    }
    return Font.custom(name, size: size)
  }
}

#Preview {
  CompassBoardView(
    viewModel: CompassBoardViewModel(initialSnapshot: .preview)
  )
  .frame(width: 1100, height: 900)
}
