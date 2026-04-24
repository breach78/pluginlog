import AppKit
import Foundation

@MainActor
enum ProjectDetailSelectionDiagnostics {
  private static let debugPrefix = "[ProjectDetailSelectionDebug]"
  private static let fileURL: URL = {
    let documentsURL =
      FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let directoryURL = documentsURL
      .appendingPathComponent("brainunfog", isDirectory: true)
      .appendingPathComponent("diagnostics", isDirectory: true)
    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL.appendingPathComponent("project-detail-selection.log", isDirectory: false)
  }()

  private static let queue = DispatchQueue(label: "BUF.project-detail-selection-diagnostics")

  static var currentLogURL: URL { fileURL }

  static func resetLog() {
    let fileURL = Self.fileURL
    queue.async {
      try? "".write(to: fileURL, atomically: true, encoding: .utf8)
    }
  }

  static func write(_ message: String) {
    let formatter = ISO8601DateFormatter()
    let timestamp = formatter.string(from: .now)
    let line = "[\(timestamp)] \(debugPrefix) \(message)\n"
    if let data = line.data(using: .utf8) {
      try? FileHandle.standardError.write(contentsOf: data)
    }
    let fileURL = Self.fileURL
    queue.async {
      let existing = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
      try? (existing + line).write(to: fileURL, atomically: true, encoding: .utf8)
    }
  }

  static func log(_ message: String) {
    AppLogger.ui.notice("\(debugPrefix, privacy: .public) \(message, privacy: .public)")
    write(message)
  }

  static func describeResponder(_ responder: NSResponder?) -> String {
    guard let responder else { return "nil" }
    let typeName = String(describing: type(of: responder))
    if let textView = responder as? NSTextView {
      return "\(typeName)(editable=\(textView.isEditable), selectable=\(textView.isSelectable))"
    }
    if let control = responder as? NSControl {
      let hasEditor = control.currentEditor() != nil
      return "\(typeName)(currentEditor=\(hasEditor))"
    }
    return typeName
  }

  static func describeModifiers(_ event: NSEvent) -> String {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    var parts: [String] = []
    if flags.contains(.shift) { parts.append("shift") }
    if flags.contains(.control) { parts.append("control") }
    if flags.contains(.option) { parts.append("option") }
    if flags.contains(.command) { parts.append("command") }
    return parts.isEmpty ? "none" : parts.joined(separator: "+")
  }
}
