import Foundation
import Testing

@testable import WorkspacePanes

@Suite("Workspace pane tree")
struct WorkspacePaneTreeTests {
  @Test("initial tree has one selected leaf")
  func initialTreeHasOneSelectedLeaf() {
    let id = paneID(1)
    let tree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: id)))

    #expect(tree.leaves.map(\.id) == [id])
    #expect(tree.selectedPaneId == id)
    #expect(tree.root == .leaf(WorkspacePaneLeaf(id: id)))
  }

  @Test("initial tree can track the root pane cwd")
  func initialTreeCanTrackRootPaneCwd() {
    let id = paneID(1)
    let cwd = URL(fileURLWithPath: "/Users/alice/src/smoovmux")
    let tree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: id, cwd: cwd)))

    #expect(tree.selectedPane?.cwd == cwd)
    #expect(tree.lastKnownCwd == cwd)
  }

  @Test("invalid initial selection falls back to first leaf")
  func invalidInitialSelectionFallsBackToFirstLeaf() throws {
    let first = paneID(1)
    let second = paneID(2)
    let root = split(
      id: paneID(10),
      direction: .right,
      first: .leaf(WorkspacePaneLeaf(id: first)),
      second: .leaf(WorkspacePaneLeaf(id: second))
    )

    let tree = WorkspacePaneTree(root: root, selectedPaneId: paneID(99))
    let encodedInvalidSelectionJSON = """
      {
        "root": {
          "leaf": {
            "_0": {
              "id": "00000000-0100-0000-0000-000000000000"
            }
          }
        },
        "selectedPaneId": "00000000-6300-0000-0000-000000000000"
      }
      """
    let encodedInvalidSelection = Data(encodedInvalidSelectionJSON.utf8)
    let decoded = try JSONDecoder().decode(WorkspacePaneTree.self, from: encodedInvalidSelection)

    #expect(tree.selectedPaneId == first)
    #expect(decoded.selectedPaneId == decoded.leaves[0].id)
  }

  @Test("selecting an unknown pane is ignored")
  func selectingUnknownPaneIsIgnored() {
    let first = paneID(1)
    var tree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: first)))

    let didSelect = tree.selectPane(paneID(99))

    #expect(didSelect == false)
    #expect(tree.selectedPaneId == first)
  }

  @Test("splitting selected pane appends new leaf and selects it")
  func splittingSelectedPaneAppendsAndSelectsNewLeaf() {
    let first = paneID(1)
    let second = paneID(2)
    let splitId = paneID(10)
    var tree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: first)))

    let newPaneId = tree.splitSelectedPane(direction: .right, newPaneId: second, splitId: splitId)

    #expect(newPaneId == second)
    #expect(tree.selectedPaneId == second)
    #expect(tree.leaves.map(\.id) == [first, second])
    #expect(
      tree.root
        == split(
          id: splitId,
          direction: .right,
          first: .leaf(WorkspacePaneLeaf(id: first)),
          second: .leaf(WorkspacePaneLeaf(id: second))
        )
    )
  }

  @Test("splitting selected pane inherits its cwd")
  func splittingSelectedPaneInheritsCwd() {
    let first = paneID(1)
    let second = paneID(2)
    let cwd = URL(fileURLWithPath: "/Users/alice/src/smoovmux")
    var tree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: first, cwd: cwd)))

    tree.splitSelectedPane(direction: .right, newPaneId: second, splitId: paneID(10))

    #expect(tree.leaves.map(\.cwd) == [cwd, cwd])
    #expect(tree.selectedPane?.cwd == cwd)
  }

  @Test("updating a pane cwd updates last known cwd")
  func updatingPaneCwdUpdatesLastKnownCwd() {
    let first = paneID(1)
    let cwd = URL(fileURLWithPath: "/tmp/repo")
    var tree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: first)))

    let didUpdate = tree.updateCwd(cwd, for: first)

    #expect(didUpdate == true)
    #expect(tree.selectedPane?.cwd == cwd)
    #expect(tree.lastKnownCwd == cwd)
  }

  @Test("split direction is preserved for vertical split")
  func splitDirectionIsPreserved() {
    let first = paneID(1)
    let second = paneID(2)
    let splitId = paneID(10)
    var tree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: first)))

    tree.splitSelectedPane(direction: .down, newPaneId: second, splitId: splitId)

    #expect(
      tree.root
        == split(
          id: splitId,
          direction: .down,
          first: .leaf(WorkspacePaneLeaf(id: first)),
          second: .leaf(WorkspacePaneLeaf(id: second))
        )
    )
  }

  @Test("splitting a non-existent pane is ignored")
  func splittingMissingPaneIsIgnored() {
    let first = paneID(1)
    var tree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: first)))

    let newPaneId = tree.splitPane(paneID(99), direction: .right, newPaneId: paneID(2), splitId: paneID(10))

    #expect(newPaneId == nil)
    #expect(tree.root == .leaf(WorkspacePaneLeaf(id: first)))
    #expect(tree.selectedPaneId == first)
  }

  @Test("closing root pane is ignored")
  func closingRootPaneIsIgnored() {
    let first = paneID(1)
    var tree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(id: first)))

    let didClose = tree.closeSelectedPane()

    #expect(didClose == false)
    #expect(tree.root == .leaf(WorkspacePaneLeaf(id: first)))
    #expect(tree.selectedPaneId == first)
  }

  @Test("closing a leaf promotes its sibling and selects it")
  func closingLeafPromotesSibling() {
    let first = paneID(1)
    let second = paneID(2)
    var tree = WorkspacePaneTree(
      root: split(
        id: paneID(10),
        direction: .right,
        first: .leaf(WorkspacePaneLeaf(id: first)),
        second: .leaf(WorkspacePaneLeaf(id: second))
      ),
      selectedPaneId: second
    )

    let didClose = tree.closeSelectedPane()

    #expect(didClose == true)
    #expect(tree.root == .leaf(WorkspacePaneLeaf(id: first)))
    #expect(tree.selectedPaneId == first)
  }

  @Test("nested same-axis splits balance by visible leaf count")
  func nestedSameAxisSplitsBalanceByLeafCount() {
    let first = paneID(1)
    let second = paneID(2)
    let third = paneID(3)
    let innerSplitId = paneID(10)
    let outerSplitId = paneID(11)
    let tree = WorkspacePaneTree(
      root: split(
        id: outerSplitId,
        direction: .right,
        first: .leaf(WorkspacePaneLeaf(id: first)),
        second: split(
          id: innerSplitId,
          direction: .right,
          first: .leaf(WorkspacePaneLeaf(id: second)),
          second: .leaf(WorkspacePaneLeaf(id: third))
        )
      )
    )

    let fractions = tree.balancedSplitFractions

    #expect(fractions[outerSplitId] == 1.0 / 3.0)
    #expect(fractions[innerSplitId] == 0.5)
  }

  @Test("mixed-axis splits balance each group independently")
  func mixedAxisSplitsBalanceIndependently() {
    let first = paneID(1)
    let second = paneID(2)
    let third = paneID(3)
    let innerSplitId = paneID(10)
    let outerSplitId = paneID(11)
    let tree = WorkspacePaneTree(
      root: split(
        id: outerSplitId,
        direction: .right,
        first: .leaf(WorkspacePaneLeaf(id: first)),
        second: split(
          id: innerSplitId,
          direction: .down,
          first: .leaf(WorkspacePaneLeaf(id: second)),
          second: .leaf(WorkspacePaneLeaf(id: third))
        )
      )
    )

    let fractions = tree.balancedSplitFractions

    #expect(fractions[outerSplitId] == 0.5)
    #expect(fractions[innerSplitId] == 0.5)
  }

  @Test("closing nested leaf collapses only its parent split")
  func closingNestedLeafCollapsesParent() {
    let first = paneID(1)
    let second = paneID(2)
    let third = paneID(3)
    let innerSplitId = paneID(10)
    let outerSplitId = paneID(11)
    var tree = WorkspacePaneTree(
      root: split(
        id: outerSplitId,
        direction: .right,
        first: split(
          id: innerSplitId,
          direction: .down,
          first: .leaf(WorkspacePaneLeaf(id: first)),
          second: .leaf(WorkspacePaneLeaf(id: second))
        ),
        second: .leaf(WorkspacePaneLeaf(id: third))
      ),
      selectedPaneId: second
    )

    let didClose = tree.closeSelectedPane()

    #expect(didClose == true)
    #expect(tree.selectedPaneId == first)
    #expect(
      tree.root
        == split(
          id: outerSplitId,
          direction: .right,
          first: .leaf(WorkspacePaneLeaf(id: first)),
          second: .leaf(WorkspacePaneLeaf(id: third))
        )
    )
  }
}

private func split(
  id: UUID,
  direction: WorkspacePaneSplitDirection,
  first: WorkspacePaneNode,
  second: WorkspacePaneNode
) -> WorkspacePaneNode {
  .split(WorkspacePaneSplit(id: id, direction: direction, first: first, second: second))
}

private func paneID(_ value: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}
