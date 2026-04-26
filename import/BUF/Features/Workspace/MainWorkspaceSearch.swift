import AppKit
import SwiftUI

extension MainWorkspaceView {
  @ViewBuilder
  func workspaceSearchResultsPanelHost(
    frame: CGRect?,
    results: [WorkspaceSearchResult],
    isVisible: Bool
  ) -> some View {
    GeometryReader { proxy in
      if let panelFrame = workspaceSearchPanelFrame(
        anchorFrame: frame,
        results: results,
        isVisible: isVisible
      ) {
        ZStack(alignment: .topLeading) {
          WorkspaceSearchInputShield(
            panelFrame: panelFrame,
            anchorFrame: frame,
            onDismiss: {
              dismissWorkspaceSearchPanel()
            }
          )
          .frame(width: proxy.size.width, height: proxy.size.height)
          .zIndex(5)

          workspaceSearchResultsPanel(results: results)
            .frame(width: panelFrame.width, height: panelFrame.height, alignment: .topLeading)
            .position(x: panelFrame.midX, y: panelFrame.midY)
            .zIndex(6)
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
      }
    }
    .animation(workspacePanelTransitionAnimation, value: isVisible)
  }

  func workspaceSearchPanelFrame(
    anchorFrame: CGRect?,
    results: [WorkspaceSearchResult],
    isVisible: Bool
  ) -> CGRect? {
    guard isVisible, let anchorFrame else { return nil }
    return CGRect(
      x: anchorFrame.minX,
      y: anchorFrame.maxY + workspaceSearchPanelOffset,
      width: workspaceSearchPanelWidth,
      height: workspaceSearchPanelHitTestHeight(for: results)
    )
  }

  func workspaceSearchPanelHitTestHeight(for results: [WorkspaceSearchResult]) -> CGFloat {
    guard !results.isEmpty else { return 48 }
    let sectionCount = Set(results.compactMap(\.disposition.sectionHeaderTitle)).count
    let estimatedHeight =
      8
      + CGFloat(results.count) * 68
      + CGFloat(sectionCount) * 32
    return min(workspaceSearchPanelMaxHeight + 12, estimatedHeight)
  }

  func workspaceSearchField(
    searchResults: [WorkspaceSearchResult],
    selectedSearchResult: WorkspaceSearchResult?
  ) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      WorkspaceSearchInputField(
        text: $chromeState.workspaceSearchQuery,
        isFocused: $chromeState.workspaceSearchFocused,
        focusRequestID: chromeState.workspaceSearchFocusRequestID,
        placeholder: "전체 검색",
        onMoveUp: {
          guard !searchResults.isEmpty else { return }
          chromeState.selectedWorkspaceSearchResultIndex = max(
            chromeState.selectedWorkspaceSearchResultIndex - 1,
            0
          )
        },
        onMoveDown: {
          guard !searchResults.isEmpty else { return }
          chromeState.selectedWorkspaceSearchResultIndex = min(
            chromeState.selectedWorkspaceSearchResultIndex + 1,
            searchResults.count - 1
          )
        },
        onSubmit: {
          guard let result = selectedSearchResult else { return }
          openWorkspaceSearchResult(result)
        },
        onEscape: {
          if !chromeState.workspaceSearchQuery.isEmpty {
            clearWorkspaceSearch()
          } else {
            chromeState.dismissWorkspaceSearch()
          }
        }
      )
      .frame(maxWidth: .infinity)

      if !chromeState.workspaceSearchQuery.isEmpty {
        Button {
          clearWorkspaceSearch()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 7)
    .frame(
      minWidth: workspaceSearchFieldMinWidth, idealWidth: workspaceSearchFieldIdealWidth,
      maxWidth: workspaceSearchFieldIdealWidth, alignment: .leading
    )
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color(nsColor: .textBackgroundColor))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
    }
    .background {
      GeometryReader { proxy in
        Color.clear.preference(
          key: WorkspaceSearchFieldFramePreferenceKey.self,
          value: proxy.frame(in: .named(Self.mainPaneCoordinateSpaceName))
        )
      }
    }
    .contentShape(Rectangle())
    .simultaneousGesture(
      TapGesture().onEnded {
        focusWorkspaceSearch()
      })
  }

  func workspaceSearchResultsPanel(results: [WorkspaceSearchResult]) -> some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        if results.isEmpty {
          Text("검색 결과 없음")
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } else {
          ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                if shouldShowWorkspaceSearchSectionHeader(at: index, in: results) {
                  Text(result.disposition.sectionHeaderTitle ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, index == 0 ? 2 : 10)
                    .padding(.bottom, 6)
                }

                workspaceSearchResultRow(index: index, result: result)
                  .id(result.id)

                if shouldShowWorkspaceSearchDivider(after: index, in: results) {
                  Divider()
                    .padding(.leading, 12)
                }
              }
            }
            .padding(.vertical, 4)
          }
          .frame(maxHeight: workspaceSearchPanelMaxHeight)
          .scrollIndicators(.automatic)
          .onAppear {
            scrollWorkspaceSearchSelectionIfNeeded(with: proxy, results: results)
          }
          .onChange(of: chromeState.selectedWorkspaceSearchResultIndex) { _, _ in
            scrollWorkspaceSearchSelectionIfNeeded(with: proxy, results: results)
          }
          .onChange(of: results.map(\.id)) { _, _ in
            scrollWorkspaceSearchSelectionIfNeeded(with: proxy, results: results)
          }
        }
      }
    }
    .frame(width: workspaceSearchPanelWidth, alignment: .leading)
    .contentShape(Rectangle())
    .overlaySurface(
      cornerRadius: 12,
      strokeColor: .secondary,
      style: workspacePresentationCardStyle
    )
    .transition(.offset(y: -4).combined(with: .opacity))
  }

  func clearWorkspaceSearch() {
    chromeState.clearWorkspaceSearch()
  }

  func workspaceSearchResultRow(index: Int, result: WorkspaceSearchResult) -> some View {
    Button {
      openWorkspaceSearchResult(result)
    } label: {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: result.entityKind == .project ? "folder" : "checklist")
          .foregroundStyle(workspaceSearchIconColor(for: result))
          .frame(width: 14, alignment: .top)
          .padding(.top, 2)

        VStack(alignment: .leading, spacing: 4) {
          Text(result.title)
            .foregroundStyle(workspaceSearchTitleColor(for: result))
            .lineLimit(2)
            .multilineTextAlignment(.leading)

          Text(workspaceSearchSubtitleText(for: result))
            .font(.caption)
            .foregroundStyle(workspaceSearchSubtitleColor(for: result))
            .lineLimit(1)
            .multilineTextAlignment(.leading)

          if let preview = workspaceSearchPreviewText(for: result) {
            Text(preview)
              .font(.caption)
              .foregroundStyle(workspaceSearchPreviewColor(for: result))
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
              .multilineTextAlignment(.leading)
          }
        }

        Spacer(minLength: 0)
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(
          index == chromeState.selectedWorkspaceSearchResultIndex
            ? Color.accentColor.opacity(0.14) : .clear)
    )
    .contentShape(Rectangle())
  }

  func openWorkspaceSearchResult(_ result: WorkspaceSearchResult) {
    showArchive = false
    chromeState.dismissWorkspaceSearch()

    if result.entityKind == .project {
      openProjectPage(for: result.navigationTarget.projectID, fallbackTitle: result.title)
      return
    }

    if let taskID = result.navigationTarget.taskID {
      openProjectTaskInSource(projectID: result.navigationTarget.projectID, taskID: taskID)
      return
    }

    openProjectPage(for: result.navigationTarget.projectID)
  }

  func dismissWorkspaceSearchPanel() {
    guard chromeState.workspaceSearchFocused else { return }
    chromeState.dismissWorkspaceSearch()
    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
      if isWorkspaceSearchFirstResponder(in: window) {
        appState.platformUIFoundation.windowManager.endEditingInFrontWindow()
      }
    }
  }

  func focusWorkspaceSearch() {
    appState.platformUIFoundation.windowManager.endEditingInFrontWindow()
    appState.platformUIFoundation.windowManager.makeMainWindowKeyAndFront()
    chromeState.focusWorkspaceSearch()
  }

  func isWorkspaceSearchFirstResponder(in window: NSWindow) -> Bool {
    guard let responder = window.firstResponder else { return false }

    if let view = responder as? NSView, view.identifier == .workspaceSearchField {
      return true
    }

    if let textView = responder as? NSTextView,
      let field = textView.delegate as? NSView,
      field.identifier == .workspaceSearchField
    {
      return true
    }

    if let control = responder as? NSControl, control.identifier == .workspaceSearchField {
      return true
    }

    return false
  }

  func workspaceSearchPreviewText(for result: WorkspaceSearchResult) -> String? {
    let preview = result.preview.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !preview.isEmpty else { return nil }

    if result.matchKind == .projectTitle || result.matchKind == .taskTitle {
      return nil
    }

    if preview.compare(
      result.title.trimmingCharacters(in: .whitespacesAndNewlines),
      options: [.caseInsensitive, .diacriticInsensitive],
      range: nil,
      locale: .autoupdatingCurrent
    ) == .orderedSame {
      return nil
    }

    return preview
  }

  func workspaceSearchSubtitleText(for result: WorkspaceSearchResult) -> String {
    if let statusLabel = result.disposition.statusLabel {
      return "\(statusLabel) · \(result.subtitle)"
    }
    return result.subtitle
  }

  func workspaceSearchIconColor(for result: WorkspaceSearchResult) -> Color {
    if result.disposition.isDimmed {
      return .secondary.opacity(0.82)
    }
    return result.entityKind == .project ? .blue : .secondary
  }

  func workspaceSearchTitleColor(for result: WorkspaceSearchResult) -> Color {
    result.disposition.isDimmed ? .secondary : .primary
  }

  func workspaceSearchSubtitleColor(for result: WorkspaceSearchResult) -> Color {
    result.disposition.isDimmed ? .secondary.opacity(0.9) : .secondary
  }

  func workspaceSearchPreviewColor(for result: WorkspaceSearchResult) -> Color {
    result.disposition.isDimmed ? .secondary.opacity(0.78) : .secondary
  }

  func shouldShowWorkspaceSearchSectionHeader(
    at index: Int,
    in results: [WorkspaceSearchResult]
  ) -> Bool {
    guard results.indices.contains(index) else { return false }
    let result = results[index]
    guard result.disposition.sectionHeaderTitle != nil else { return false }
    guard index > 0 else { return true }
    return results[index - 1].disposition.sectionRank != result.disposition.sectionRank
  }

  func shouldShowWorkspaceSearchDivider(
    after index: Int,
    in results: [WorkspaceSearchResult]
  ) -> Bool {
    let nextIndex = index + 1
    guard results.indices.contains(index), results.indices.contains(nextIndex) else { return false }
    return results[index].disposition.sectionRank == results[nextIndex].disposition.sectionRank
  }

  func scrollWorkspaceSearchSelectionIfNeeded(
    with proxy: ScrollViewProxy,
    results: [WorkspaceSearchResult]
  ) {
    guard results.indices.contains(chromeState.selectedWorkspaceSearchResultIndex) else { return }
    let resultID = results[chromeState.selectedWorkspaceSearchResultIndex].id

    DispatchQueue.main.async {
      MotionTransaction.perform(
        .scrollToTarget,
        quality: workspacePresentationMotionQuality
      ) {
        proxy.scrollTo(resultID, anchor: .center)
      }
    }
  }
}

private struct WorkspaceSearchInputShield: View {
  let panelFrame: CGRect
  let anchorFrame: CGRect?
  let onDismiss: () -> Void

  var body: some View {
    GeometryReader { proxy in
      ForEach(
        Array(shieldRects(in: CGRect(origin: .zero, size: proxy.size)).enumerated()),
        id: \.offset
      ) { _, rect in
        Color.clear
          .contentShape(Rectangle())
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
          .onTapGesture {
            onDismiss()
          }
      }
    }
  }

  private func shieldRects(in bounds: CGRect) -> [CGRect] {
    let excludedRect = (anchorFrame?.union(panelFrame) ?? panelFrame)
      .insetBy(dx: -2, dy: -2)
      .intersection(bounds)
    guard !excludedRect.isNull, !excludedRect.isEmpty else { return [bounds] }

    return [
      CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: excludedRect.minY),
      CGRect(
        x: bounds.minX,
        y: excludedRect.minY,
        width: excludedRect.minX,
        height: excludedRect.height
      ),
      CGRect(
        x: excludedRect.maxX,
        y: excludedRect.minY,
        width: bounds.maxX - excludedRect.maxX,
        height: excludedRect.height
      ),
      CGRect(
        x: bounds.minX,
        y: excludedRect.maxY,
        width: bounds.width,
        height: bounds.maxY - excludedRect.maxY
      ),
    ]
    .filter { $0.width > 0 && $0.height > 0 }
  }
}
