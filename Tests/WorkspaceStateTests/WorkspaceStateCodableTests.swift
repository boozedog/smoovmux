import Foundation
import Testing
import WorkspacePanes
import WorkspaceSidebar
import WorkspaceState
import WorkspaceTabs

@Suite("Workspace state persistence")
struct WorkspaceStateCodableTests {
  @Test("round trips tab order, selected tab, split tree, pane cwd, and window frame")
  func roundTripsWorkspaceState() throws {
    let firstTab = tabID(1)
    let secondTab = tabID(2)
    let firstPane = paneID(1)
    let secondPane = paneID(2)
    let split = paneID(10)
    let firstCwd = URL(fileURLWithPath: "/Users/alice/src/smoovmux")
    let secondCwd = URL(fileURLWithPath: "/tmp/build")

    let paneTree = WorkspacePaneTree(
      root: .split(
        WorkspacePaneSplit(
          id: split,
          direction: .right,
          first: .leaf(WorkspacePaneLeaf(id: firstPane, cwd: firstCwd)),
          second: .leaf(WorkspacePaneLeaf(id: secondPane, cwd: secondCwd, command: "pi"))
        )
      ),
      selectedPaneId: secondPane
    )

    let state = WorkspaceState(
      tabs: [
        WorkspaceState.Tab(
          record: WorkspaceTabRecord(id: firstTab, title: "smoovmux", cwd: firstCwd, usesAutomaticTitle: true),
          paneTree: paneTree
        ),
        WorkspaceState.Tab(
          record: WorkspaceTabRecord(id: secondTab, title: "custom", cwd: secondCwd, usesAutomaticTitle: false),
          paneTree: WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: paneID(3), cwd: secondCwd)))
        ),
      ],
      selectedTabId: secondTab,
      windowFrame: WorkspaceWindowFrame(x: 10, y: 20, width: 1200, height: 800),
      leftSidebar: WorkspaceLeftSidebarState(isOpen: false),
      rightSidebar: WorkspaceRightSidebarState(isOpen: true, width: 380)
    )

    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

    #expect(decoded == state)
    #expect(decoded.tabs.map(\.record.id) == [firstTab, secondTab])
    #expect(decoded.selectedTabId == secondTab)
    #expect(decoded.tabs[0].paneTree == paneTree)
    #expect(decoded.tabs[0].paneTree.leaves[1].command == "pi")
    #expect(decoded.windowFrame == WorkspaceWindowFrame(x: 10, y: 20, width: 1200, height: 800))
    #expect(decoded.leftSidebar == WorkspaceLeftSidebarState(isOpen: false))
    #expect(decoded.rightSidebar == WorkspaceRightSidebarState(isOpen: true, width: 380))
  }

  @Test("decodes old state files without right sidebar")
  func decodesStateWithoutRightSidebar() throws {
    let json = """
      {
        "selectedTabId": "00000001-0000-0000-0000-000000000000",
        "tabs": [
          {
            "record": {
              "id": "00000001-0000-0000-0000-000000000000",
              "title": "one",
              "usesAutomaticTitle": false
            },
            "paneTree": {
              "root": {
                "leaf": {
                  "_0": {
                    "id": "00000000-0100-0000-0000-000000000000"
                  }
                }
              },
              "selectedPaneId": "00000000-0100-0000-0000-000000000000"
            }
          }
        ]
      }
      """

    let decoded = try JSONDecoder().decode(WorkspaceState.self, from: Data(json.utf8))

    #expect(decoded.leftSidebar == WorkspaceLeftSidebarState())
    #expect(decoded.rightSidebar == WorkspaceRightSidebarState())
  }

  @Test("normalizes invalid selected tab and empty workspaces")
  func normalizesInvalidSelection() throws {
    let tab = WorkspaceState.Tab(
      record: WorkspaceTabRecord(id: tabID(1), title: "one"),
      paneTree: WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: paneID(1))))
    )

    let state = WorkspaceState(tabs: [tab], selectedTabId: tabID(99), windowFrame: nil)
    let empty = WorkspaceState(tabs: [], selectedTabId: tabID(99), windowFrame: nil)

    let encodedInvalidSelectionJSON = """
      {
        "selectedTabId": "00000063-0000-0000-0000-000000000000",
        "tabs": [
          {
            "record": {
              "id": "00000001-0000-0000-0000-000000000000",
              "title": "one",
              "usesAutomaticTitle": false
            },
            "paneTree": {
              "root": {
                "leaf": {
                  "_0": {
                    "id": "00000000-0100-0000-0000-000000000000"
                  }
                }
              },
              "selectedPaneId": "00000000-0100-0000-0000-000000000000"
            }
          }
        ]
      }
      """
    let encodedInvalidSelection = Data(encodedInvalidSelectionJSON.utf8)
    let decoded = try JSONDecoder().decode(WorkspaceState.self, from: encodedInvalidSelection)

    #expect(state.selectedTabId == tab.record.id)
    #expect(empty.tabs.count == 1)
    #expect(empty.selectedTabId == empty.tabs[0].record.id)
    #expect(decoded.selectedTabId == decoded.tabs[0].record.id)
  }
}

private func tabID(_ value: UInt8) -> UUID {
  UUID(uuid: (value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

private func paneID(_ value: UInt8) -> UUID {
  UUID(uuid: (0, value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
