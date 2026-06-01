import Foundation

enum ProjectOutlineTextInsertionPolicy {
  static func insert(_ insertion: String, into text: String, utf16Offset: Int) -> String {
    let nsText = text as NSString
    let clampedOffset = min(max(0, utf16Offset), nsText.length)
    return nsText.replacingCharacters(
      in: NSRange(location: clampedOffset, length: 0),
      with: insertion
    )
  }
}
