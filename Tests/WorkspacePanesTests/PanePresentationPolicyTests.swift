import Foundation
import Testing

@testable import WorkspacePanes

@Suite("Pane presentation policy")
struct PanePresentationPolicyTests {
  @Test("selected terminal title trims blanks")
  func selectedTerminalTitleTrimsBlanks() {
    let selected = paneID(1)

    #expect(
      PanePresentationPolicy.selectedTerminalTitle(
        selectedPaneId: selected,
        titlesByPaneId: [selected: "  vim  "]
      ) == "vim"
    )
    #expect(
      PanePresentationPolicy.selectedTerminalTitle(
        selectedPaneId: selected,
        titlesByPaneId: [selected: "  \n"]
      ) == nil
    )
    #expect(
      PanePresentationPolicy.selectedTerminalTitle(
        selectedPaneId: selected,
        titlesByPaneId: [:]
      ) == nil
    )
  }

  @Test("window title shows cwd and command")
  func windowTitleShowsCwdAndCommand() {
    let leaf = WorkspacePaneLeaf(
      id: paneID(1),
      cwd: URL(fileURLWithPath: "/Users/alice/src/smoovmux"),
      command: "lazygit"
    )

    #expect(
      PanePresentationPolicy.windowTitle(for: leaf, homePath: "/Users/alice")
        == "~/src/smoovmux — lazygit"
    )
  }

  @Test("window title falls back to shell and home")
  func windowTitleFallsBackToShellAndHome() {
    #expect(PanePresentationPolicy.windowTitle(for: nil, homePath: "/Users/alice") == "~ — shell")
    #expect(
      PanePresentationPolicy.windowTitle(
        for: WorkspacePaneLeaf(id: paneID(1)),
        homePath: "/Users/alice"
      ) == "~ — shell"
    )
  }
}

private func paneID(_ value: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}
