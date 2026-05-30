import AppKit
import SwiftUI
import Testing
@testable import BrainUnfog

@MainActor
struct EscapeAwareTextFieldCommandTests {
  @Test func insertTabRunsOptionalTabCommand() {
    var didRunTab = false
    var text = ""
    var isFocused = true
    let field = EscapeAwareTextField(
      text: Binding(get: { text }, set: { text = $0 }),
      isFocused: Binding(get: { isFocused }, set: { isFocused = $0 }),
      placeholder: "새 할일",
      onSubmit: {},
      onEscape: {},
      onTab: {
        didRunTab = true
      }
    )
    let coordinator = EscapeAwareTextField.Coordinator(parent: field)

    let handled = coordinator.control(
      NSControl(),
      textView: NSTextView(),
      doCommandBy: #selector(NSResponder.insertTab(_:))
    )

    #expect(handled)
    #expect(didRunTab)
  }

  @Test func insertTabFallsThroughWithoutTabCommand() {
    var text = ""
    var isFocused = true
    let field = EscapeAwareTextField(
      text: Binding(get: { text }, set: { text = $0 }),
      isFocused: Binding(get: { isFocused }, set: { isFocused = $0 }),
      placeholder: "새 할일",
      onSubmit: {},
      onEscape: {}
    )
    let coordinator = EscapeAwareTextField.Coordinator(parent: field)

    let handled = coordinator.control(
      NSControl(),
      textView: NSTextView(),
      doCommandBy: #selector(NSResponder.insertTab(_:))
    )

    #expect(!handled)
  }
}
