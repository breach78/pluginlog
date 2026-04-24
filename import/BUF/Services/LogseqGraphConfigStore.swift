import Foundation

struct LogseqGraphConfigStore {
  private static let internalIdentityPropertyNames = [
    "brain_unfog_project_id",
    "brain_unfog_task_id",
    "calendar_event_external_id",
    "reminder_external_id",
    "reminder_list_external_id",
  ]
  private static let internalIdentityPropertyAliases = internalIdentityPropertyNames.flatMap {
    [$0, $0.replacingOccurrences(of: "_", with: "-")]
  }
  private static let visibleSchedulePropertyNames = [
    "date",
    "duration",
    "repeat",
  ]
  private static let completedTaskMarkerNames = [
    "done",
    "canceled",
    "cancelled",
  ]
  private static let cssBlockStart = "/* Brain Unfog internal identity properties: begin */"
  private static let cssBlockEnd = "/* Brain Unfog internal identity properties: end */"

  private let graphRootURL: URL
  private let fileManager: FileManager

  init(graphRootURL: URL, fileManager: FileManager = .default) {
    self.graphRootURL = graphRootURL
    self.fileManager = fileManager
  }

  func ensureInternalIdentityPropertiesHidden(hideCompletedTasks: Bool = true) throws {
    let logseqURL = graphRootURL.appendingPathComponent("logseq", isDirectory: true)
    try fileManager.createDirectory(at: logseqURL, withIntermediateDirectories: true)

    let configURL = logseqURL.appendingPathComponent("config.edn", isDirectory: false)
    let originalContents: String
    if fileManager.fileExists(atPath: configURL.path) {
      originalContents = try String(contentsOf: configURL, encoding: .utf8)
    } else {
      originalContents = "{:meta/version 1}\n"
    }

    let updatedContents = Self.updatingConfig(originalContents)
    if updatedContents != originalContents {
      try updatedContents.write(to: configURL, atomically: true, encoding: .utf8)
    }

    let customCSSURL = logseqURL.appendingPathComponent("custom.css", isDirectory: false)
    let originalCSS: String
    if fileManager.fileExists(atPath: customCSSURL.path) {
      originalCSS = try String(contentsOf: customCSSURL, encoding: .utf8)
    } else {
      originalCSS = ""
    }

    let updatedCSS = Self.updatingCustomCSS(
      originalCSS,
      hideCompletedTasks: hideCompletedTasks
    )
    guard updatedCSS != originalCSS else { return }
    try updatedCSS.write(to: customCSSURL, atomically: true, encoding: .utf8)
  }

  static func updatingConfig(_ contents: String) -> String {
    let hiddenProperties = internalIdentityPropertyAliases.map { ":\($0)" }
    let withHiddenProperties = upsertingSet(
      settingKey: ":block-hidden-properties",
      requiredValues: hiddenProperties,
      in: contents
    )
    return upsertingSet(
      settingKey: ":property-pages/excludelist",
      requiredValues: hiddenProperties,
      in: withHiddenProperties
    )
  }

  static func updatingCustomCSS(_ contents: String, hideCompletedTasks: Bool = true) -> String {
    let managedBlock = managedCustomCSSBlock(hideCompletedTasks: hideCompletedTasks)
    guard let startRange = contents.range(of: cssBlockStart) else {
      return appendingManagedCSSBlock(managedBlock, to: contents)
    }

    guard let endRange = contents.range(of: cssBlockEnd, range: startRange.upperBound..<contents.endIndex)
    else {
      return appendingManagedCSSBlock(managedBlock, to: contents)
    }

    var updatedContents = contents
    updatedContents.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: managedBlock)
    return updatedContents
  }

  private static func upsertingSet(
    settingKey: String,
    requiredValues: [String],
    in contents: String
  ) -> String {
    var lines = contents.components(separatedBy: .newlines)
    if let lineIndex = lines.firstIndex(where: { isActiveSettingLine($0, settingKey: settingKey) }) {
      let existingValues = setValues(from: lines[lineIndex])
      lines[lineIndex] = settingLine(
        settingKey: settingKey,
        values: existingValues + requiredValues,
        replacing: lines[lineIndex]
      )
      return lines.joined(separator: "\n")
    }

    return insertingSettingLine(
      "\(settingKey) \(formattedSet(requiredValues))",
      into: contents
    )
  }

  private static func isActiveSettingLine(_ line: String, settingKey: String) -> Bool {
    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
    return trimmedLine.hasPrefix(settingKey + " ")
  }

  private static func setValues(from line: String) -> [String] {
    guard let startRange = line.range(of: "#{"),
      let endIndex = line[startRange.upperBound...].firstIndex(of: "}"),
      startRange.upperBound < endIndex
    else {
      return []
    }

    return line[startRange.upperBound..<endIndex]
      .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
      .map(String.init)
  }

  private static func settingSuffix(from line: String) -> String {
    guard let startRange = line.range(of: "#{"),
      let endIndex = line[startRange.upperBound...].firstIndex(of: "}")
    else {
      return ""
    }

    return String(line[line.index(after: endIndex)...])
  }

  private static func settingLine(
    settingKey: String,
    values: [String],
    replacing line: String
  ) -> String {
    "\(leadingWhitespace(in: line))\(settingKey) \(formattedSet(values))\(settingSuffix(from: line))"
  }

  private static func formattedSet(_ values: [String]) -> String {
    let sortedValues = Array(Set(values)).sorted()
    return "#{\(sortedValues.joined(separator: " "))}"
  }

  private static func leadingWhitespace(in line: String) -> String {
    String(line.prefix { $0 == " " || $0 == "\t" })
  }

  private static func insertingSettingLine(_ settingLine: String, into contents: String) -> String {
    guard let closingBraceIndex = contents.lastIndex(of: "}") else {
      return contents + "\n \(settingLine)\n"
    }

    let beforeClosingBrace = contents[..<closingBraceIndex]
    let afterClosingBrace = contents[closingBraceIndex...]
    let separator = beforeClosingBrace.last == "\n" ? "" : "\n"
    return "\(beforeClosingBrace)\(separator) \(settingLine)\n\(afterClosingBrace)"
  }

  private static func managedCustomCSSBlock(hideCompletedTasks: Bool) -> String {
    let hiddenSelectors = internalIdentityPropertyAliases
      .map { "div.block-properties > div:has(a[data-ref=\"\($0)\" i])" }
      .joined(separator: ",\n")
    let chipContainerSelector = visibleSchedulePropertyNames
      .map {
        "div.block-properties:not(.page-properties):has(a[data-ref=\"\($0)\" i])"
      }
      .joined(separator: ",\n")
    let blockContentRowSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-content:has(div.block-properties:not(.page-properties) a[data-ref=\"\($0)\" i])"
      }
      .joined(separator: ",\n")
    let blockContentWrapperRowSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-content-wrapper:has(div.block-properties:not(.page-properties) a[data-ref=\"\($0)\" i]),\ndiv.flex.flex-col.block-content-wrapper:has(div.block-properties:not(.page-properties) a[data-ref=\"\($0)\" i])"
      }
      .joined(separator: ",\n")
    let blockContentTitleSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-content:has(div.block-properties:not(.page-properties) a[data-ref=\"\($0)\" i]) > div.block-content-inner"
      }
      .joined(separator: ",\n")
    let blockContentWrapperTitleSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-content-wrapper:has(div.block-properties:not(.page-properties) a[data-ref=\"\($0)\" i]) > .flex.flex-row,\ndiv.flex.flex-col.block-content-wrapper:has(div.block-properties:not(.page-properties) a[data-ref=\"\($0)\" i]) > .flex.flex-row"
      }
      .joined(separator: ",\n")
    let blockContentOuterColumnSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-content-wrapper > div.flex.flex-row > div.flex-1.w-full:has(> div.block-content div.block-properties:not(.page-properties) a[data-ref=\"\($0)\" i])"
      }
      .joined(separator: ",\n")
    let blockContentInnerTitleSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-content:has(> div.block-properties:not(.page-properties) a[data-ref=\"\($0)\" i]) > div.block-content-inner > div.flex-1.w-full"
      }
      .joined(separator: ",\n")
    let chipSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-properties:not(.page-properties) > div:has(a[data-ref=\"\($0)\" i])"
      }
      .joined(separator: ",\n")
    let chipLinkSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-properties:not(.page-properties) > div:has(a[data-ref=\"\($0)\" i]) a"
      }
      .joined(separator: ",\n")
    let chipLabelSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-properties:not(.page-properties) > div:has(a[data-ref=\"\($0)\" i]) > div:first-child"
      }
      .joined(separator: ",\n")
    let chipSeparatorSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-properties:not(.page-properties) > div:has(a[data-ref=\"\($0)\" i]) > span.mr-1"
      }
      .joined(separator: ",\n")
    let chipValueSelectors = visibleSchedulePropertyNames
      .map {
        "div.block-properties:not(.page-properties) > div:has(a[data-ref=\"\($0)\" i]) > div.page-property-value"
      }
      .joined(separator: ",\n")
    let completedTaskSelectors = completedTaskHidingSelectors().joined(separator: ",\n")
    let completedTaskFilterCSS =
      hideCompletedTasks
      ? """

    /* Brain Unfog completed task filter */
    \(completedTaskSelectors) {
      display: none !important;
    }
    """
      : ""

    return """
    \(cssBlockStart)
    \(hiddenSelectors) {
      display: none !important;
    }
    \(completedTaskFilterCSS)

    /* Brain Unfog schedule chips */
    \(blockContentRowSelectors) {
      display: flex !important;
      flex-direction: row !important;
      align-items: baseline !important;
      flex-wrap: wrap !important;
      column-gap: 8px;
      row-gap: 2px;
      width: 100% !important;
      max-width: 100%;
      min-width: 0;
      vertical-align: baseline;
    }

    \(blockContentWrapperRowSelectors) {
      display: flex !important;
      flex-direction: row !important;
      align-items: baseline !important;
      flex-wrap: wrap !important;
      column-gap: 8px;
      row-gap: 2px;
      max-width: 100%;
      min-width: 0;
    }

    \(blockContentOuterColumnSelectors) {
      display: flex !important;
      flex: 1 1 auto !important;
      width: 100% !important;
      max-width: 100%;
      min-width: 0;
    }

    \(blockContentTitleSelectors),
    \(blockContentWrapperTitleSelectors),
    \(blockContentInnerTitleSelectors) {
      flex: 1 1 auto !important;
      width: auto !important;
      min-width: 0;
    }

    div.block-content-inner:has(+ div.block-properties:not(.page-properties) a[data-ref="date" i]),
    div.block-content-inner:has(+ div.block-properties:not(.page-properties) a[data-ref="duration" i]),
    div.block-content-inner:has(+ div.block-properties:not(.page-properties) a[data-ref="repeat" i]),
    div.block-content-inner:has(~ div.block-properties:not(.page-properties) a[data-ref="date" i]),
    div.block-content-inner:has(~ div.block-properties:not(.page-properties) a[data-ref="duration" i]),
    div.block-content-inner:has(~ div.block-properties:not(.page-properties) a[data-ref="repeat" i]) {
      display: inline !important;
    }

    \(chipContainerSelector) {
      display: inline-flex !important;
      flex-wrap: wrap;
      align-items: center;
      flex: 0 0 auto;
      gap: 4px;
      margin-left: auto !important;
      width: auto !important;
      max-width: min(56vw, 560px);
      margin-top: 0 !important;
      margin-right: 0 !important;
      margin-bottom: 0 !important;
      padding: 0 !important;
      border: 0 !important;
      background: transparent !important;
      box-shadow: none !important;
      position: static !important;
      transform: none !important;
      vertical-align: baseline;
    }

    \(chipSelectors) {
      display: inline-flex !important;
      align-items: center;
      gap: 4px;
      width: auto !important;
      margin: 0 !important;
      padding: 1px 8px !important;
      border: 0 !important;
      border-radius: 4px;
      background: rgba(238, 240, 243, 0.92) !important;
      color: rgba(50, 56, 66, 0.9);
      font-size: 0.72em;
      font-weight: 600;
      line-height: 1.55;
      box-shadow: none !important;
    }

    \(chipLabelSelectors),
    \(chipSeparatorSelectors) {
      display: none !important;
    }

    \(chipValueSelectors) {
      display: inline-flex !important;
      align-items: center;
      margin: 0 !important;
    }

    \(chipLinkSelectors) {
      color: inherit !important;
      opacity: 0.72;
      font-weight: 700;
      text-decoration: none !important;
    }
    \(cssBlockEnd)
    """
  }

  private static func completedTaskHidingSelectors() -> [String] {
    let markerSelectors = completedTaskMarkerNames.flatMap { marker in
      [
        "div.ls-block:has(> div.flex.flex-row .block-content-inner .marker-switch.\(marker))",
        "div.ls-block:has(> div.flex.flex-row .block-content-inner .marker-switch.\(marker.uppercased()))",
        "div.ls-block:has(> div.flex.flex-row .block-content-inner .\(marker))",
        "div.ls-block:has(> div.flex.flex-row .block-content-inner .\(marker.uppercased()))",
        "div.ls-block:has(> div.flex.flex-row .block-content-inner a[data-ref=\"\(marker)\" i])",
        "div.ls-block[data-refs-self*=\"\(marker)\" i]",
      ]
    }
    return [
      "div.ls-block:has(> div.flex.flex-row input[type=\"checkbox\"]:checked)",
      "div.ls-block:has(> div.flex.flex-row .form-checkbox:checked)",
      "div.ls-block:has(> div.flex.flex-row .form-checkbox.checked)",
    ] + markerSelectors
  }

  private static func appendingManagedCSSBlock(_ block: String, to contents: String) -> String {
    let trimmedContents = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedContents.isEmpty else {
      return block + "\n"
    }

    return trimmedContents + "\n\n" + block + "\n"
  }
}
