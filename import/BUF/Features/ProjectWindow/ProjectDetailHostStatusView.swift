import SwiftUI

struct ProjectDetailHostStatusView: View {
  enum State: Equatable {
    case loading
    case failure(ProjectDetailBlockPageLoadFailure?)
  }

  let state: State
  let onRetry: (() -> Void)?

  var body: some View {
    switch state {
    case .loading:
      ProjectDetailHostLoadingView()
    case .failure(let failure):
      ProjectDetailHostFailureView(
        failure: failure,
        onRetry: onRetry
      )
    }
  }
}

private struct ProjectDetailHostLoadingView: View {
  var body: some View {
    VStack(spacing: 12) {
      ProgressView()
        .controlSize(.small)

      Text("프로젝트 페이지를 준비 중입니다")
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ProjectDetailHostFailureView: View {
  let failure: ProjectDetailBlockPageLoadFailure?
  let onRetry: (() -> Void)?

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.secondary)

      VStack(spacing: 6) {
        Text(failure?.title ?? "프로젝트 페이지를 열 수 없습니다")
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(.primary)

        Text(failure?.message ?? "프로젝트 페이지를 다시 불러오지 못했습니다")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
      }

      if let onRetry, failure?.allowsRetry ?? true {
        Button("다시 시도", action: onRetry)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }
}
