import Foundation
import Testing

@testable import WorkspaceTabs

@Suite("Workspace tab list")
struct WorkspaceTabListTests {
  @Test("adding the first tab selects it and assigns the default title")
  func addFirstTabSelectsIt() {
    var list = WorkspaceTabList()
    let id = tabID(1)

    let tab = list.addTab(id: id)

    #expect(tab.id == id)
    #expect(tab.title == "Terminal 1")
    #expect(list.tabs == [tab])
    #expect(list.selectedTabId == id)
    #expect(list.selectedTab == tab)
  }

  @Test("adding a tab without selecting preserves the current selected tab")
  func addWithoutSelectingPreservesSelection() {
    var list = WorkspaceTabList()
    let first = tabID(1)
    let second = tabID(2)
    list.addTab(id: first)

    list.addTab(id: second, select: false)

    #expect(list.tabs.map(\.id) == [first, second])
    #expect(list.selectedTabId == first)
  }

  @Test("adding a selected tab updates selection")
  func addSelectedTabUpdatesSelection() {
    var list = WorkspaceTabList()
    let first = tabID(1)
    let second = tabID(2)
    list.addTab(id: first)

    list.addTab(id: second)

    #expect(list.selectedTabId == second)
  }

  @Test("selecting an unknown tab is ignored")
  func selectingUnknownTabIsIgnored() {
    var list = WorkspaceTabList()
    let first = tabID(1)
    let unknown = tabID(99)
    list.addTab(id: first)

    let didSelect = list.selectTab(unknown)

    #expect(didSelect == false)
    #expect(list.selectedTabId == first)
  }

  @Test("closing the selected middle tab selects the next tab")
  func closingSelectedMiddleTabSelectsNextTab() {
    var list = WorkspaceTabList()
    let first = tabID(1)
    let second = tabID(2)
    let third = tabID(3)
    list.addTab(id: first)
    list.addTab(id: second)
    list.addTab(id: third)
    list.selectTab(second)

    let didClose = list.closeTab(second)

    #expect(didClose == true)
    #expect(list.tabs.map(\.id) == [first, third])
    #expect(list.selectedTabId == third)
  }

  @Test("closing the selected last tab selects the new last tab")
  func closingSelectedLastTabSelectsPreviousTab() {
    var list = WorkspaceTabList()
    let first = tabID(1)
    let second = tabID(2)
    list.addTab(id: first)
    list.addTab(id: second)

    list.closeTab(second)

    #expect(list.tabs.map(\.id) == [first])
    #expect(list.selectedTabId == first)
  }

  @Test("closing a non-selected tab preserves selection")
  func closingNonSelectedTabPreservesSelection() {
    var list = WorkspaceTabList()
    let first = tabID(1)
    let second = tabID(2)
    list.addTab(id: first)
    list.addTab(id: second)
    list.selectTab(first)

    list.closeTab(second)

    #expect(list.tabs.map(\.id) == [first])
    #expect(list.selectedTabId == first)
  }

  @Test("closing the only tab is ignored")
  func closingOnlyTabIsIgnored() {
    var list = WorkspaceTabList()
    let first = tabID(1)
    list.addTab(id: first)

    let didClose = list.closeTab(first)

    #expect(didClose == false)
    #expect(list.tabs.map(\.id) == [first])
    #expect(list.selectedTabId == first)
  }

  @Test("next and previous selection wrap around")
  func nextAndPreviousSelectionWrap() {
    var list = WorkspaceTabList()
    let first = tabID(1)
    let second = tabID(2)
    list.addTab(id: first)
    list.addTab(id: second)

    list.selectNextTab()
    #expect(list.selectedTabId == first)

    list.selectPreviousTab()
    #expect(list.selectedTabId == second)
  }
}

private func tabID(_ value: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}
