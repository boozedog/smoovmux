import Testing

@testable import SmoovAppCommands

@Suite("App command shortcuts")
struct AppCommandTests {
  @Test("all commands have user-visible titles")
  func allCommandsHaveTitles() {
    for command in AppCommand.allCases {
      #expect(command.title.isEmpty == false)
    }
  }

  @Test("shortcut-bearing commands do not collide")
  func shortcutsDoNotCollide() {
    let shortcuts = AppCommand.allCases.compactMap(\.shortcut)

    #expect(Set(shortcuts).count == shortcuts.count)
  }

  @Test("new tab is Command-T")
  func newTabShortcut() {
    #expect(AppCommand.newTab.shortcut == KeyboardShortcutSpec(key: "t", modifiers: [.command]))
  }

  @Test("next and previous tab shortcuts use square brackets")
  func tabNavigationShortcuts() {
    #expect(AppCommand.nextTab.shortcut == KeyboardShortcutSpec(key: "]", modifiers: [.command]))
    #expect(AppCommand.previousTab.shortcut == KeyboardShortcutSpec(key: "[", modifiers: [.command]))
  }

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

  @Test("toggle git sidebar is Command-Shift-G")
  func toggleGitSidebarShortcut() {
    #expect(AppCommand.toggleRightSidebar.shortcut == KeyboardShortcutSpec(key: "g", modifiers: [.command, .shift]))
  }

  @Test("close tab no longer owns Command-W")
  func closeTabDoesNotUseCommandW() {
    #expect(AppCommand.closeTab.shortcut != KeyboardShortcutSpec(key: "w", modifiers: [.command]))
  }
}
