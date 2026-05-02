import Testing

@testable import SmoovAppCommands

@Suite("App command shortcuts")
struct AppCommandTests {
  @Test("split right is Command-D")
  func splitRightShortcut() {
    #expect(AppCommand.splitRight.shortcut == KeyboardShortcutSpec(key: "d", modifiers: [.command]))
  }

  @Test("split down is Command-Shift-D")
  func splitDownShortcut() {
    #expect(AppCommand.splitDown.shortcut == KeyboardShortcutSpec(key: "D", modifiers: [.command, .shift]))
  }

  @Test("close pane is Command-W")
  func closePaneShortcut() {
    #expect(AppCommand.closePane.shortcut == KeyboardShortcutSpec(key: "w", modifiers: [.command]))
  }

  @Test("close tab no longer owns Command-W")
  func closeTabDoesNotUseCommandW() {
    #expect(AppCommand.closeTab.shortcut != KeyboardShortcutSpec(key: "w", modifiers: [.command]))
  }
}
