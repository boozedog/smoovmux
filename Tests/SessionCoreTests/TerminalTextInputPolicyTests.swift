import Foundation
import Testing

@testable import SessionCore

@Suite("Terminal text input policy")
struct TerminalTextInputPolicyTests {
  @Test("key text prefers non-empty composed text over fallback")
  func keyTextPrefersComposedText() {
    #expect(TerminalTextInputPolicy.keyText(composed: "é", fallback: "e") == "é")
    #expect(TerminalTextInputPolicy.keyText(composed: "", fallback: "a") == "a")
    #expect(TerminalTextInputPolicy.keyText(composed: nil, fallback: "b") == "b")
  }

  @Test("key payload sends printable text only")
  func keyPayloadSendsPrintableTextOnly() {
    #expect(TerminalTextInputPolicy.keyPayload("a") == "a")
    #expect(TerminalTextInputPolicy.keyPayload("😀") == "😀")
    #expect(TerminalTextInputPolicy.keyPayload("") == nil)
    #expect(TerminalTextInputPolicy.keyPayload("\r") == nil)
    #expect(TerminalTextInputPolicy.keyPayload("\u{1b}") == nil)
  }

  @Test("text insertion extracts strings and attributed strings")
  func textInsertionExtractsSupportedTypes() {
    #expect(TerminalTextInputPolicy.insertionText(from: "hello") == "hello")
    #expect(TerminalTextInputPolicy.insertionText(from: NSAttributedString(string: "world")) == "world")
    #expect(TerminalTextInputPolicy.insertionText(from: "") == nil)
    #expect(TerminalTextInputPolicy.insertionText(from: 42) == nil)
  }

  @Test("paste payload preserves multiline strings")
  func pastePayloadPreservesMultilineStrings() {
    let payload = String(repeating: "line one\nline two\n", count: 1024)

    #expect(TerminalTextInputPolicy.textPayload(payload) == payload)
  }

  @Test("paste payload ignores empty strings")
  func pastePayloadIgnoresEmptyStrings() {
    #expect(TerminalTextInputPolicy.textPayload("paste") == "paste")
    #expect(TerminalTextInputPolicy.textPayload("") == nil)
  }
}
