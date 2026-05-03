import Testing

@testable import SessionCore

@Suite("Terminal clipboard policy")
struct TerminalClipboardPolicyTests {
  @Test("direct paste may read the standard clipboard")
  func directPasteMayReadStandardClipboard() {
    #expect(TerminalClipboardPolicy.allowsRead(kind: .standard, request: .paste))
  }

  @Test("OSC 52 reads and selection clipboards are denied by default")
  func osc52ReadsAndSelectionClipboardsAreDeniedByDefault() {
    #expect(!TerminalClipboardPolicy.allowsRead(kind: .standard, request: .osc52Read))
    #expect(!TerminalClipboardPolicy.allowsRead(kind: .selection, request: .paste))
    #expect(!TerminalClipboardPolicy.allowsRead(kind: .primary, request: .paste))
  }

  @Test("OSC 52 writes require confirmation and standard clipboard")
  func osc52WritesRequireConfirmation() {
    #expect(TerminalClipboardPolicy.allowsWrite(kind: .standard, request: .osc52Write, confirmed: true))
    #expect(!TerminalClipboardPolicy.allowsWrite(kind: .standard, request: .osc52Write, confirmed: false))
    #expect(!TerminalClipboardPolicy.allowsWrite(kind: .selection, request: .osc52Write, confirmed: true))
  }
}
