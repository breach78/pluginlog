import AppKit
import Foundation
import SwiftUI

extension JournalBoardView {
  var journalPresentationMotionContext: MotionContext {
    MotionContext(
      tier: .presentation,
      isTyping: appState.isEditorMotionSuppressed
    )
  }

  var journalPresentationMotionQuality: MotionQuality {
    MotionSystem.quality(for: journalPresentationMotionContext)
  }

  var journalPaperSurfaceStyle: OverlaySurfaceStyle {
    switch journalPresentationMotionQuality {
    case .full:
      return OverlaySurfaceStyle(
        cornerRadius: 0,
        fillOpacity: 1,
        strokeOpacity: 0.05,
        strokeWidth: 1,
        shadowOpacity: 0.05,
        shadowRadius: 18,
        shadowX: 0,
        shadowY: 8,
        useCompositingGroup: false
      )
    case .reduced:
      return OverlaySurfaceStyle(
        cornerRadius: 0,
        fillOpacity: 1,
        strokeOpacity: 0.045,
        strokeWidth: 1,
        shadowOpacity: 0.03,
        shadowRadius: 10,
        shadowX: 0,
        shadowY: 4,
        useCompositingGroup: false
      )
    case .minimal, .disabled:
      return OverlaySurfaceStyle(
        cornerRadius: 0,
        fillOpacity: 1,
        strokeOpacity: 0.04,
        strokeWidth: 1,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowX: 0,
        shadowY: 0,
        useCompositingGroup: false
      )
    }
  }

  var journalChromeButtonSurfaceStyle: OverlaySurfaceStyle {
    switch journalPresentationMotionQuality {
    case .full:
      return OverlaySurfaceStyle(
        cornerRadius: 8,
        fillOpacity: 0.035,
        strokeOpacity: 0.05,
        strokeWidth: 0.7,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowX: 0,
        shadowY: 0,
        useCompositingGroup: false
      )
    case .reduced:
      return OverlaySurfaceStyle(
        cornerRadius: 8,
        fillOpacity: 0.032,
        strokeOpacity: 0.04,
        strokeWidth: 0.7,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowX: 0,
        shadowY: 0,
        useCompositingGroup: false
      )
    case .minimal, .disabled:
      return OverlaySurfaceStyle(
        cornerRadius: 8,
        fillOpacity: 0.028,
        strokeOpacity: 0.03,
        strokeWidth: 0.6,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowX: 0,
        shadowY: 0,
        useCompositingGroup: false
      )
    }
  }

  var journalDetailPopoverSurfaceStyle: OverlaySurfaceStyle {
    OverlaySurfaceStyle.card(quality: journalPresentationMotionQuality)
  }

  var journalBoardRoot: some View {
    ScrollViewReader { proxy in
      journalBoardSurface(using: proxy)
    }
  }

  func journalBoardSurface(using proxy: ScrollViewProxy) -> some View {
    ZStack {
      journalBoardBackgroundLayer
      journalBoardViewport
    }
    .task(id: reloadSignature) {
      guard isActive else { return }
      await prepareJournalBoard(forceScroll: !didAutoScrollToToday)
    }
    .task(id: isActive) {
      guard isActive else { return }
      await monitorCalendarDayBoundary()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: .reminderAppJournalEntriesDidChange)
    ) { _ in
      journalSourceRevision += 1
    }
    .onChange(of: isDraftFocused) { _, isFocused in
      if isFocused {
        appState.beginEditorSession(id: editorSessionID)
      } else {
        draftAutosaveTask?.cancel()
        appState.endEditorSession(id: editorSessionID)
        Task {
          await commitDraftIfNeeded()
        }
      }
    }
    .onChange(of: journalDraft) { _, _ in
      guard !isApplyingDraftSeed else { return }
      isDraftDirty = true
      scheduleDraftAutosave()
    }
    .onChange(of: scrollRequestID) { _, _ in
      scrollToBottom(using: proxy, animated: false)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
        isDraftFocused = true
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        guard needsInitialViewportPin else { return }
        scrollToBottom(using: proxy, animated: false)
        needsInitialViewportPin = false
      }
    }
    .onChange(of: isActive) { _, active in
      guard !active else { return }
      draftAutosaveTask?.cancel()
      isDraftFocused = false
      appState.endEditorSession(id: editorSessionID)
      Task {
        await commitDraftIfNeeded(force: true)
      }
    }
    .onDisappear {
      draftAutosaveTask?.cancel()
      appState.endEditorSession(id: editorSessionID)
      Task {
        await commitDraftIfNeeded(force: true)
      }
    }
  }

  var journalBoardBackgroundLayer: some View {
    Color(nsColor: .windowBackgroundColor)
      .ignoresSafeArea()
  }

  var journalBoardViewport: some View {
    HStack(alignment: .top, spacing: 0) {
      Spacer(minLength: 24)
      journalPaperColumn
      Spacer(minLength: 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  var journalPaperColumn: some View {
    VStack(alignment: .leading, spacing: 0) {
      journalChromeSection
      journalDayFeedSection
    }
    .frame(maxWidth: journalPaperWidth, maxHeight: .infinity, alignment: .topLeading)
    .overlaySurface(
      cornerRadius: 0,
      fillColor: Color(nsColor: .textBackgroundColor),
      strokeColor: .black,
      style: journalPaperSurfaceStyle
    )
  }

  var journalChromeSection: some View {
    Group {
      header
        .padding(.horizontal, 52)
        .padding(.top, 36)
        .padding(.bottom, 22)

      Divider()
    }
  }

  var journalDayFeedSection: some View {
    ScrollView {
      journalDaySectionList
    }
  }

  var journalDaySectionList: some View {
    LazyVStack(alignment: .leading, spacing: 30) {
      ForEach(preparedDaySections) { section in
        daySection(section)
          .id(section.id)
      }

      journalScrollBottomAnchor
    }
    .padding(.horizontal, 52)
    .padding(.vertical, 32)
  }

  var journalScrollBottomAnchor: some View {
    Color.clear
      .frame(height: 1)
      .id(Self.scrollBottomKey)
  }

  var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Journals")
        .font(JournalTypography.font(size: 28, weight: .bold))

      HStack(spacing: 10) {
        Text("우물 쭈물 살다가 내 이럴 줄 알았다.")
          .font(JournalTypography.font(size: 13))
          .foregroundStyle(.secondary)

        if preparedDaySections.isEmpty && (isLoadingEntries || isPreparingSections) {
          ProgressView()
            .controlSize(.small)
        }
      }
    }
  }

  func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
    DispatchQueue.main.async {
      let scrollAction = {
        proxy.scrollTo(Self.scrollBottomKey, anchor: .bottom)
      }
      if animated {
        MotionTransaction.perform(
          .scrollToTarget,
          context: journalPresentationMotionContext,
          body: scrollAction
        )
      } else {
        MotionTransaction.withoutAnimation(scrollAction)
      }
    }
  }
}
