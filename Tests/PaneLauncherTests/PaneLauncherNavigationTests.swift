import PaneLauncher
import Testing

@Suite("Pane launcher navigation")
struct PaneLauncherNavigationTests {
  @Test("list selection wraps with arrow keys")
  func listSelectionWraps() {
    var state = PaneLauncherNavigationState(rowCount: 5)

    #expect(state.selectedIndex == 0)
    #expect(state.handle(.up) == nil)
    #expect(state.selectedIndex == 4)
    #expect(state.handle(.down) == nil)
    #expect(state.selectedIndex == 0)
  }

  @Test("number picks one-based row when in range")
  func numberPicksOneBasedRow() {
    var state = PaneLauncherNavigationState(rowCount: 5)

    #expect(state.handle(.number(3)) == .pick(index: 2))
    #expect(state.selectedIndex == 2)
    #expect(state.handle(.number(9)) == nil)
    #expect(state.selectedIndex == 2)
  }

  @Test("enter picks selected row and escape launches shell in list mode")
  func enterAndEscapeInListMode() {
    var state = PaneLauncherNavigationState(rowCount: 5)
    state.selectedIndex = 2

    #expect(state.handle(.enter) == .pick(index: 2))
    #expect(state.handle(.escape) == .launchShell)
  }

  @Test("custom mode escape returns to list and enter launches custom command")
  func customModeKeys() {
    var state = PaneLauncherNavigationState(rowCount: 5)
    state.mode = .custom

    #expect(state.handle(.escape) == nil)
    #expect(state.mode == .list)

    state.mode = .custom
    #expect(state.handle(.enter) == .launchCustom)
  }
}
