import Foundation
import UniformTypeIdentifiers

enum TaskDragPayload {
  static let textTypeIdentifier = UTType.text.identifier
  static let taskPrefix = "buf-task:"

  static func payloadString(for taskID: UUID) -> String {
    "\(taskPrefix)\(taskID.uuidString)"
  }

  static func itemProvider(for taskID: UUID) -> NSItemProvider {
    NSItemProvider(object: payloadString(for: taskID) as NSString)
  }

  static func parseTaskID(from item: NSSecureCoding?) -> UUID? {
    guard let payload = DragPayloadCodec.decodeTextPayload(from: item) else { return nil }
    return parseTaskID(from: payload)
  }

  static func parseTaskID(from payload: String) -> UUID? {
    DragPayloadCodec.parseTaskID(
      from: payload,
      taskPrefix: taskPrefix,
      projectPrefix: ProjectDragPayload.projectPrefix
    )
  }
}

enum ProjectDragPayload {
  static let textTypeIdentifier = UTType.text.identifier
  static let projectType = UTType(exportedAs: "com.brainunfog.timeline-project")
  static let projectPrefix = "buf-project:"

  static func payloadString(for projectID: UUID) -> String {
    "\(projectPrefix)\(projectID.uuidString)"
  }

  static func itemProvider(for projectID: UUID) -> NSItemProvider {
    let payload = payloadString(for: projectID)
    let provider = NSItemProvider(object: payload as NSString)
    provider.registerDataRepresentation(
      forTypeIdentifier: projectType.identifier,
      visibility: .all
    ) { completion in
      completion(payload.data(using: .utf8), nil)
      return nil
    }
    return provider
  }

  static func parseProjectID(from item: NSSecureCoding?) -> UUID? {
    guard let payload = DragPayloadCodec.decodeTextPayload(from: item) else { return nil }
    return DragPayloadCodec.parseUUID(from: payload, prefix: projectPrefix)
  }
}
