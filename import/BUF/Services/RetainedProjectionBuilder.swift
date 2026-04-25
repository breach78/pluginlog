import CryptoKit
import Foundation

enum RetainedProjectionBuilder {
  enum Error: LocalizedError, Equatable {
    case duplicateProjectID(UUID)
    case duplicateReminderListExternalIdentifier(String)
    case duplicateTaskID(UUID)
    case duplicateReminderExternalIdentifier(String)
    case duplicateCalendarEventExternalIdentifier(String)
    case damagedProjectIdentity(pageTitle: String)
    case conflictingProjectIdentity(pageTitle: String)
    case damagedTaskIdentity(projectTitle: String, taskTitle: String)
    case missingPageForProjectBinding(projectID: UUID, reminderListExternalIdentifier: String)
    case orphanTaskBinding(taskID: UUID)

    var errorDescription: String? {
      switch self {
      case .duplicateProjectID(let projectID):
        return "중복된 retained project id가 발견되었습니다. (\(projectID.uuidString))"
      case .duplicateReminderListExternalIdentifier(let identifier):
        return "중복된 reminder list external id가 발견되었습니다. (\(identifier))"
      case .duplicateTaskID(let taskID):
        return "중복된 retained task id가 발견되었습니다. (\(taskID.uuidString))"
      case .duplicateReminderExternalIdentifier(let identifier):
        return "중복된 reminder external id가 발견되었습니다. (\(identifier))"
      case .duplicateCalendarEventExternalIdentifier(let identifier):
        return "중복된 calendar event external id가 발견되었습니다. (\(identifier))"
      case .damagedProjectIdentity(let pageTitle):
        return "프로젝트 identity가 손상되어 retained projection을 만들 수 없습니다. (\(pageTitle))"
      case .conflictingProjectIdentity(let pageTitle):
        return "프로젝트 identity와 reminder identity가 충돌합니다. (\(pageTitle))"
      case .damagedTaskIdentity(let projectTitle, let taskTitle):
        return "할일 identity가 손상되어 retained projection을 만들 수 없습니다. (\(projectTitle) / \(taskTitle))"
      case .missingPageForProjectBinding(let projectID, let reminderListExternalIdentifier):
        return "retained project binding에 대응하는 노트를 찾지 못했습니다. (\(projectID.uuidString), \(reminderListExternalIdentifier))"
      case .orphanTaskBinding(let taskID):
        return "retained task binding이 안전하게 연결될 할일을 찾지 못했습니다. (\(taskID.uuidString))"
      }
    }
  }

  static func derivedProjectID(for reminderListExternalIdentifier: String) -> UUID {
    deterministicUUID(namespace: "reminder-project", key: reminderListExternalIdentifier)
  }

  private static func deterministicUUID(namespace: String, key: String) -> UUID {
    let digest = SHA256.hash(data: Data("\(namespace)|\(key)".utf8))
    var bytes = Array(digest.prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}
