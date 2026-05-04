import Foundation
import Testing

@testable import WorkspaceTabs

@Suite("Right sidebar refresh policy")
struct RightSidebarRefreshPolicyTests {
  @Test("same git root with existing pane is kept during automatic refresh")
  func sameGitRootWithExistingPaneIsKeptDuringAutomaticRefresh() {
    let root = URL(fileURLWithPath: "/tmp/repo")

    #expect(
      !RightSidebarRefreshPolicy.shouldOpenPane(
        currentGitRoot: root,
        requestedGitRoot: root,
        hasExistingPane: true,
        forceRestart: false
      )
    )
  }

  @Test("manual refresh restarts existing pane even for same git root")
  func manualRefreshRestartsExistingPaneForSameGitRoot() {
    let root = URL(fileURLWithPath: "/tmp/repo")

    #expect(
      RightSidebarRefreshPolicy.shouldOpenPane(
        currentGitRoot: root,
        requestedGitRoot: root,
        hasExistingPane: true,
        forceRestart: true
      )
    )
  }

  @Test("different git root opens a new pane without force")
  func differentGitRootOpensNewPaneWithoutForce() {
    #expect(
      RightSidebarRefreshPolicy.shouldOpenPane(
        currentGitRoot: URL(fileURLWithPath: "/tmp/repo-a"),
        requestedGitRoot: URL(fileURLWithPath: "/tmp/repo-b"),
        hasExistingPane: true,
        forceRestart: false
      )
    )
  }

  @Test("missing pane opens a pane for current git root")
  func missingPaneOpensPaneForCurrentGitRoot() {
    let root = URL(fileURLWithPath: "/tmp/repo")

    #expect(
      RightSidebarRefreshPolicy.shouldOpenPane(
        currentGitRoot: root,
        requestedGitRoot: root,
        hasExistingPane: false,
        forceRestart: false
      )
    )
  }
}
