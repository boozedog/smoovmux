import Foundation
import Testing
import WorkspacePanes
import WorkspaceState
import WorkspaceTabs

@Suite("App workspace state")
struct AppWorkspaceStateTests {
  @Test("round trips multiple windows and selected window")
  func roundTripsMultipleWindows() throws {
    let firstWindow = windowID(1)
    let secondWindow = windowID(2)
    let firstWorkspace = WorkspaceState(
      tabs: [tab(id: tabID(1), title: "one")],
      selectedTabId: tabID(1),
      windowFrame: WorkspaceWindowFrame(x: 10, y: 20, width: 900, height: 600)
    )
    let secondWorkspace = WorkspaceState(
      tabs: [tab(id: tabID(2), title: "two")],
      selectedTabId: tabID(2),
      windowFrame: WorkspaceWindowFrame(x: 40, y: 50, width: 1000, height: 700)
    )

    let state = AppWorkspaceState(
      windows: [
        AppWorkspaceState.Window(id: firstWindow, workspace: firstWorkspace),
        AppWorkspaceState.Window(id: secondWindow, workspace: secondWorkspace),
      ],
      selectedWindowId: secondWindow
    )

    let decoded = try JSONDecoder().decode(AppWorkspaceState.self, from: try JSONEncoder().encode(state))

    #expect(decoded == state)
    #expect(decoded.windows.map(\.id) == [firstWindow, secondWindow])
    #expect(decoded.selectedWindowId == secondWindow)
  }

  @Test("normalizes invalid selected window without creating windows")
  func normalizesInvalidSelectedWindow() {
    let validWindow = windowID(1)

    let state = AppWorkspaceState(
      windows: [AppWorkspaceState.Window(id: validWindow, workspace: .empty())],
      selectedWindowId: windowID(99)
    )
    let empty = AppWorkspaceState(windows: [], selectedWindowId: windowID(99))

    #expect(state.selectedWindowId == validWindow)
    #expect(empty.windows.isEmpty)
    #expect(empty.selectedWindowId == nil)
  }

  @Test("empty workspaces stay empty for new-session prompt windows")
  func emptyWorkspacesStayEmpty() {
    let state = WorkspaceState(tabs: [], selectedTabId: tabID(99), windowFrame: nil)

    #expect(state.tabs.isEmpty)
    #expect(state.selectedTabId == nil)
  }
}

private func tab(id: UUID, title: String) -> WorkspaceState.Tab {
  WorkspaceState.Tab(
    record: WorkspaceTabRecord(id: id, title: title),
    paneTree: WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf()))
  )
}

private func tabID(_ value: UInt8) -> UUID {
  UUID(uuid: (value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

private func windowID(_ value: UInt8) -> UUID {
  UUID(uuid: (0, value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
