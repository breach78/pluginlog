import UniformTypeIdentifiers
import XCTest
@testable import BrainUnfog

final class TaskDragPayloadTests: XCTestCase {
  func testTaskDragPayloadRegistersCustomAndTextPayloadTypes() {
    let taskID = UUID()
    let provider = TaskDragPayload.itemProvider(for: taskID)

    XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(TaskDragPayload.typeIdentifier))
    XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(TaskDragPayload.utf8PlainTextTypeIdentifier))
    XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(TaskDragPayload.plainTextTypeIdentifier))
    XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(TaskDragPayload.textTypeIdentifier))
  }

  func testTaskDragPayloadDropTypesPreferCustomTypeThenTextFallbacks() {
    XCTAssertEqual(
      TaskDragPayload.dropTypeIdentifiers,
      [
        TaskDragPayload.typeIdentifier,
        TaskDragPayload.utf8PlainTextTypeIdentifier,
        TaskDragPayload.plainTextTypeIdentifier,
        TaskDragPayload.textTypeIdentifier,
      ]
    )
  }

  func testTaskDragPayloadRoundTripsTaskIDAndRejectsProjectPayload() {
    let taskID = UUID()

    XCTAssertEqual(
      TaskDragPayload.parseTaskID(from: TaskDragPayload.payloadString(for: taskID)),
      taskID
    )
    XCTAssertEqual(
      TaskDragPayload.parseTaskID(from: TaskDragPayload.payloadString(for: taskID) as NSString),
      taskID
    )
    XCTAssertEqual(
      TaskDragPayload.parseTaskID(from: TaskDragPayload.payloadString(for: taskID).data(using: .utf8)! as NSData),
      taskID
    )
    XCTAssertNil(TaskDragPayload.parseTaskID(from: ProjectDragPayload.payloadString(for: UUID())))
  }
}
