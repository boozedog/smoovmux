import Foundation
import Testing

@testable import WorkspaceTabs

@Suite("Right sidebar auto-open policy")
struct RightSidebarAutoOpenPolicyTests {
  @Test("opens only for matching active cwd and resolved git root")
  func opensOnlyForMatchingCwdAndGitRoot() {
    let cwd = URL(fileURLWithPath: "/tmp/repo")
    let root = URL(fileURLWithPath: "/tmp/repo")

    #expect(
      RightSidebarAutoOpenPolicy.shouldOpen(
        isSidebarOpen: false,
        requestedCwd: cwd,
        currentActiveCwd: cwd,
        resolvedGitRoot: root
      )
    )
    #expect(
      !RightSidebarAutoOpenPolicy.shouldOpen(
        isSidebarOpen: true,
        requestedCwd: cwd,
        currentActiveCwd: cwd,
        resolvedGitRoot: root
      )
    )
    #expect(
      !RightSidebarAutoOpenPolicy.shouldOpen(
        isSidebarOpen: false,
        requestedCwd: cwd,
        currentActiveCwd: URL(fileURLWithPath: "/tmp/other"),
        resolvedGitRoot: root
      )
    )
    #expect(
      !RightSidebarAutoOpenPolicy.shouldOpen(
        isSidebarOpen: false,
        requestedCwd: cwd,
        currentActiveCwd: cwd,
        resolvedGitRoot: nil
      )
    )
  }

  @Test("standardized URLs are treated as same cwd")
  func standardizedURLsMatch() {
    let requested = URL(fileURLWithPath: "/tmp/repo/./child/..")
    let active = URL(fileURLWithPath: "/tmp/repo")

    #expect(
      RightSidebarAutoOpenPolicy.shouldOpen(
        isSidebarOpen: false,
        requestedCwd: requested,
        currentActiveCwd: active,
        resolvedGitRoot: URL(fileURLWithPath: "/tmp/repo")
      )
    )
  }
}
