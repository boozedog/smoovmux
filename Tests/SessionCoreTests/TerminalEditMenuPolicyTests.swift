import Testing

@testable import SessionCore

@Suite("Terminal edit menu policy")
struct TerminalEditMenuPolicyTests {
  @Test("context menu exposes cleaned copy raw copy and paste")
  func contextMenuExposesCopyActions() {
    let items = TerminalEditMenuPolicy.items(hasSelection: true, canPaste: true)

    let allItemsAreEnabled = items.allSatisfy(\.isEnabled)

    #expect(items.map(\.title) == ["Copy", "Copy Without Cleanup", "Paste"])
    #expect(items.map(\.action) == [.copy, .copyRaw, .paste])
    #expect(allItemsAreEnabled)
  }

  @Test("copy actions require selection and paste requires pasteable content")
  func editActionsReflectAvailability() {
    let items = TerminalEditMenuPolicy.items(hasSelection: false, canPaste: false)

    #expect(
      items == [
        TerminalEditMenuItem(action: .copy, title: "Copy", isEnabled: false),
        TerminalEditMenuItem(action: .copyRaw, title: "Copy Without Cleanup", isEnabled: false),
        TerminalEditMenuItem(action: .paste, title: "Paste", isEnabled: false),
      ])
  }
}
