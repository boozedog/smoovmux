import Foundation
import Testing

@testable import WorkspaceTabs

struct RightSidebarTabStateTests {
  @Test
  func preservesPanePerSelectedTab() {
    let first = UUID()
    let second = UUID()
    let firstRoot = URL(fileURLWithPath: "/repo/one")
    let secondRoot = URL(fileURLWithPath: "/repo/two")
    var state = RightSidebarTabState<String>()

    state.setPane("first", gitRoot: firstRoot, for: first)
    state.setPane("second", gitRoot: secondRoot, for: second)

    #expect(state.pane(for: first) == "first")
    #expect(state.gitRoot(for: first) == firstRoot)
    #expect(state.pane(for: second) == "second")
    #expect(state.gitRoot(for: second) == secondRoot)
  }

  @Test
  func discardsOnlyClosedTabPane() {
    let first = UUID()
    let second = UUID()
    var state = RightSidebarTabState<String>()
    state.setPane("first", gitRoot: URL(fileURLWithPath: "/repo/one"), for: first)
    state.setPane("second", gitRoot: URL(fileURLWithPath: "/repo/two"), for: second)

    state.discardPane(for: first)

    #expect(state.pane(for: first) == nil)
    #expect(state.gitRoot(for: first) == nil)
    #expect(state.pane(for: second) == "second")
  }

  @Test
  func hidingChromeDoesNotDiscardPanes() {
    let tab = UUID()
    var state = RightSidebarTabState<String>()
    state.setPane("pane", gitRoot: URL(fileURLWithPath: "/repo"), for: tab)

    state.clearMessage(for: tab)

    #expect(state.pane(for: tab) == "pane")
    #expect(state.gitRoot(for: tab) == URL(fileURLWithPath: "/repo"))
  }
}
