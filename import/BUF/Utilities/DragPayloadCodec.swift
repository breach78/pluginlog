import Foundation

enum DragPayloadCodec {
    // Keep DnD payload decoding centralized so all boards interpret providers identically.
    static func decodeTextPayload(from item: NSSecureCoding?) -> String? {
        if let value = item as? String {
            return value
        }
        if let value = item as? NSString {
            return value as String
        }
        if let value = item as? NSData, let decoded = String(data: value as Data, encoding: .utf8) {
            return decoded
        }
        if let value = item as? URL {
            return value.absoluteString
        }
        return nil
    }

    static func parseUUID(from payload: String, prefix: String) -> UUID? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(prefix) {
            return UUID(uuidString: String(trimmed.dropFirst(prefix.count)))
        }
        return UUID(uuidString: trimmed)
    }

    static func parseTaskID(from payload: String, taskPrefix: String, projectPrefix: String) -> UUID? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(projectPrefix) {
            return nil
        }
        if trimmed.hasPrefix(taskPrefix) {
            return UUID(uuidString: String(trimmed.dropFirst(taskPrefix.count)))
        }
        return UUID(uuidString: trimmed)
    }
}
