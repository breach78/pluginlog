import Foundation
import Testing
@testable import BrainUnfog

struct TaskDragPayloadScheduleMonthTests {
  @Test func taskProviderCanBeDroppedOnScheduleMonthCells() async throws {
    let taskID = UUID()
    let provider = TaskDragPayload.itemProvider(for: taskID)

    #expect(provider.hasItemConformingToTypeIdentifier(ScheduleMonthDragPayload.typeIdentifier))

    let item = try await loadScheduleMonthDragItem(
      from: provider,
      typeIdentifier: ScheduleMonthDragPayload.typeIdentifier
    )
    #expect(item == .task(taskID))
  }

  @Test func scheduleMonthAcceptsGenericTaskTextPayload() {
    let taskID = UUID()
    let item = ScheduleMonthDragPayload.parseItem(
      from: TaskDragPayload.payloadString(for: taskID)
    )

    #expect(item == .task(taskID))
  }

  private func loadScheduleMonthDragItem(
    from provider: NSItemProvider,
    typeIdentifier: String
  ) async throws -> ScheduleMonthDragItem? {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        continuation.resume(returning: ScheduleMonthDragPayload.parseItem(from: item))
      }
    }
  }
}
