import Testing

@testable import WorkspaceSidebar

@Suite("Git sidebar toolbar policy")
struct GitSidebarToolbarPolicyTests {
  @Test("toolbar does not expose a separate focus action when lazygit is visible")
  func toolbarDoesNotExposeSeparateFocusAction() {
    #expect(GitSidebarToolbarPolicy.actions(hasPane: true) == [.refresh, .hide])
  }

  @Test("toolbar actions are stable while lazygit is unavailable")
  func toolbarActionsAreStableWithoutPane() {
    #expect(GitSidebarToolbarPolicy.actions(hasPane: false) == [.refresh, .hide])
  }
}
