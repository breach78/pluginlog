import Combine
import Foundation

@MainActor
final class BlockPageStateStore: ObservableObject {
  @Published private(set) var activeEditorBlockID: UUID?
  @Published private(set) var navigationStack: [UUID] = []
  @Published var hoveredBlockID: UUID?
  @Published var focusedBlockID: UUID?
  @Published var activeDragParentBlockID: UUID?

  let collapseContract: BlockCollapseStateContract

  private let userDefaults: UserDefaults

  init(
    userDefaults: UserDefaults = .standard,
    collapseContract: BlockCollapseStateContract = .projectDetailDefault
  ) {
    self.userDefaults = userDefaults
    self.collapseContract = collapseContract
  }

  func isExpanded(blockID: UUID, isRootBlock: Bool = false) -> Bool {
    collapseContract.resolvedIsExpanded(
      persistedValue: persistedExpansionValue(for: blockID, isRootBlock: isRootBlock),
      isRootBlock: isRootBlock
    )
  }

  func setExpanded(_ isExpanded: Bool, for blockID: UUID, isRootBlock: Bool = false) {
    guard collapseContract.persistsPerBlockDisclosureState, !isRootBlock else { return }
    let key = expansionKey(for: blockID)
    let previousValue = userDefaults.object(forKey: key) as? Bool
    guard previousValue != isExpanded else { return }
    objectWillChange.send()
    userDefaults.set(isExpanded, forKey: key)
  }

  func toggleExpansion(for blockID: UUID, isRootBlock: Bool = false) {
    let nextValue = !isExpanded(blockID: blockID, isRootBlock: isRootBlock)
    setExpanded(nextValue, for: blockID, isRootBlock: isRootBlock)
  }

  func orderingMode(for parentBlockID: UUID) -> BlockChildOrderingMode {
    let key = orderingModeKey(for: parentBlockID)
    guard
      let rawValue = userDefaults.string(forKey: key),
      let mode = BlockChildOrderingMode(rawValue: rawValue)
    else {
      return .manual
    }
    return mode
  }

  func hasStoredOrderingMode(for parentBlockID: UUID) -> Bool {
    userDefaults.object(forKey: orderingModeKey(for: parentBlockID)) != nil
  }

  func setOrderingMode(_ mode: BlockChildOrderingMode, for parentBlockID: UUID) {
    let key = orderingModeKey(for: parentBlockID)
    guard orderingMode(for: parentBlockID) != mode else { return }
    objectWillChange.send()
    userDefaults.set(mode.rawValue, forKey: key)
  }

  func orderedChildIDs(for parentBlockID: UUID) -> [UUID]? {
    let key = orderedChildIDsKey(for: parentBlockID)
    guard let rawValues = userDefaults.array(forKey: key) as? [String], !rawValues.isEmpty else {
      return nil
    }

    let ids = rawValues.compactMap(UUID.init(uuidString:))
    return ids.isEmpty ? nil : ids
  }

  func setOrderedChildIDs(_ childIDs: [UUID], for parentBlockID: UUID) {
    let key = orderedChildIDsKey(for: parentBlockID)
    let rawValues = childIDs.map(\.uuidString)
    let previousValues = userDefaults.array(forKey: key) as? [String] ?? []
    guard previousValues != rawValues else { return }
    objectWillChange.send()
    userDefaults.set(rawValues, forKey: key)
  }

  func activateEditor(for blockID: UUID?) {
    guard activeEditorBlockID != blockID else { return }
    activeEditorBlockID = blockID
  }

  func clearActiveEditor(ifMatches blockID: UUID) {
    guard activeEditorBlockID == blockID else { return }
    activeEditorBlockID = nil
  }

  func pushPage(_ pageID: UUID) {
    navigationStack.append(pageID)
  }

  @discardableResult
  func popPage() -> UUID? {
    navigationStack.popLast()
  }

  func resetNavigation() {
    navigationStack.removeAll()
  }

  private func persistedExpansionValue(for blockID: UUID, isRootBlock: Bool) -> Bool? {
    guard collapseContract.persistsPerBlockDisclosureState, !isRootBlock else { return nil }
    let key = expansionKey(for: blockID)
    guard userDefaults.object(forKey: key) != nil else { return nil }
    return userDefaults.bool(forKey: key)
  }

  private func expansionKey(for blockID: UUID) -> String {
    "blockPage.expanded.\(blockID.uuidString)"
  }

  private func orderingModeKey(for parentBlockID: UUID) -> String {
    "blockPage.orderingMode.\(parentBlockID.uuidString)"
  }

  private func orderedChildIDsKey(for parentBlockID: UUID) -> String {
    "blockPage.orderedChildren.\(parentBlockID.uuidString)"
  }
}
