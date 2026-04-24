import Foundation

@MainActor
final class UndoCoordinator: ObservableObject {
  @Published private(set) var isPerformingUndoRedo = false

  private var activeOperationCount = 0

  func register(
    with undoManager: UndoManager?,
    actionName: String,
    handler: @escaping @MainActor () -> Void
  ) {
    guard let undoManager else { return }
    undoManager.registerUndo(withTarget: self) { coordinator in
      coordinator.perform(handler)
    }
    undoManager.setActionName(actionName)
  }

  func perform(_ handler: @escaping @MainActor () -> Void) {
    beginOperation()
    handler()
    endOperation()
  }

  func performAsync(_ operation: @escaping @MainActor () async -> Void) {
    beginOperation()
    Task { @MainActor [weak self] in
      await operation()
      self?.endOperation()
    }
  }

  private func beginOperation() {
    activeOperationCount += 1
    if !isPerformingUndoRedo {
      isPerformingUndoRedo = true
    }
  }

  private func endOperation() {
    activeOperationCount = max(0, activeOperationCount - 1)
    if activeOperationCount == 0, isPerformingUndoRedo {
      isPerformingUndoRedo = false
    }
  }
}
