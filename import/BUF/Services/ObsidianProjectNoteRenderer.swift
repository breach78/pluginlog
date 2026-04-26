import Foundation

enum ObsidianProjectNoteRenderer {
  static func render(_ note: ObsidianProjectNote) -> String {
    let frontmatter = renderFrontmatter(note.frontmatter)
    let body = renderBody(note)

    guard !frontmatter.isEmpty else { return body }
    guard !body.isEmpty else { return frontmatter }
    return frontmatter + "\n" + body
  }

  private static func renderFrontmatter(_ frontmatter: ObsidianProjectFrontmatter?) -> String {
    guard let frontmatter else { return "" }

    var lines: [String] = ["---"]
    if !frontmatter.tags.isEmpty {
      lines.append("tags:")
      lines.append(contentsOf: frontmatter.tags.map { "  - \($0)" })
    }
    if let listID = normalized(frontmatter.reminderListExternalIdentifier) {
      lines.append("reminder_list_external_id: \(listID)")
      if let colorHex = normalized(frontmatter.colorHex) {
        lines.append("brain_unfog_color_hex: \(yamlQuoted(colorHex))")
      }
      lines.append("분류:")
      lines.append("  - \(frontmatter.projectStage.title)")
      lines.append(frontmatterLine(key: "시작일", value: frontmatter.startDate))
      lines.append(frontmatterLine(key: "마감일", value: frontmatter.deadline))
      lines.append("완료 가리기: \(frontmatter.hideCompletedTasks ? "true" : "false")")
      lines.append("아카이브: \(frontmatter.isArchived ? "true" : "false")")
    }
    lines.append(contentsOf: frontmatter.preservedLines.filter { line in
      !isLegacyBrainUnfogLine(line) && !isKnownCanonicalLine(line)
    })
    lines.append("---")
    return lines.joined(separator: "\n")
  }

  private static func renderBody(_ note: ObsidianProjectNote) -> String {
    let lines = note.bodyMarkdown.components(separatedBy: "\n")
    let tasksByLine = Dictionary(uniqueKeysWithValues: note.tasks.map { ($0.bodyLineIndex, $0) })
    let tasksByMetadataLine = Dictionary(
      uniqueKeysWithValues: note.tasks.compactMap { task in
        task.metadataLineIndex.map { ($0, task) }
      }
    )
    var rendered: [String] = []

    for index in lines.indices {
      if let task = tasksByMetadataLine[index] {
        if task.metadataIsDamaged {
          rendered.append(lines[index])
        } else if let metadata = task.metadata {
          rendered.append(renderMetadataLine(metadata, indentation: task.indentation + "  "))
        }
        continue
      }

      rendered.append(lines[index])
      if let task = tasksByLine[index],
        task.metadataLineIndex == nil,
        let metadata = task.metadata,
        !task.metadataIsDamaged
      {
        rendered.append(renderMetadataLine(metadata, indentation: task.indentation + "  "))
      }
    }

    return rendered.joined(separator: "\n")
  }

  private static func renderMetadataLine(
    _ metadata: ObsidianTaskMetadata,
    indentation: String
  ) -> String {
    "\(indentation)%% brain-unfog: {\(renderMetadataJSONBody(metadata))} %%"
  }

  private static func renderMetadataJSONBody(_ metadata: ObsidianTaskMetadata) -> String {
    var fields: [String] = []
    if let value = normalized(metadata.reminderExternalIdentifier) {
      fields.append(#""reminder_external_id":"\#(jsonEscaped(value))""#)
    }
    if let value = normalized(metadata.date) {
      fields.append(#""date":"\#(jsonEscaped(value))""#)
    }
    if let value = normalized(metadata.time) {
      fields.append(#""time":"\#(jsonEscaped(value))""#)
    }
    if let duration = metadata.durationMinutes {
      fields.append(#""duration":\#(duration)"#)
    }
    if let value = normalized(metadata.repeatRule) {
      fields.append(#""repeat":"\#(jsonEscaped(value))""#)
    }
    return fields.joined(separator: ",")
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return nil
    }
    return value
  }

  private static func isKnownCanonicalLine(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed == "tags:" || trimmed.hasPrefix("reminder_list_external_id:")
      || trimmed.hasPrefix("brain_unfog_color_hex:")
      || trimmed.hasPrefix("분류:")
      || trimmed.hasPrefix("시작일:")
      || trimmed.hasPrefix("마감일:")
      || trimmed.hasPrefix("완료 가리기:") || trimmed.hasPrefix("아카이브:")
  }

  private static func isLegacyBrainUnfogLine(_ line: String) -> Bool {
    let key = line.split(separator: ":", maxSplits: 1).first?
      .trimmingCharacters(in: .whitespaces)
      .lowercased()
    return key == "brain_unfog_project_id" || key == "brain_unfog_task_id"
  }

  private static func yamlQuoted(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
  }

  private static func frontmatterLine(key: String, value: String?) -> String {
    guard let value = normalized(value) else { return "\(key):" }
    return "\(key): \(value)"
  }

  private static func jsonEscaped(_ value: String) -> String {
    var result = ""
    for character in value {
      switch character {
      case "\\":
        result.append(#"\\"#)
      case "\"":
        result.append(#"\""#)
      case "\n":
        result.append(#"\n"#)
      case "\r":
        result.append(#"\r"#)
      case "\t":
        result.append(#"\t"#)
      default:
        result.append(character)
      }
    }
    return result
  }
}
