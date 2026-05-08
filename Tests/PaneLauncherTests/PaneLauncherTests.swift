import Foundation
import PaneLauncher
import Testing

@Suite("Pane launcher policy")
struct PaneLauncherTests {
  @Test("builtins match the requested launcher order")
  func builtinsMatchRequestedLauncherOrder() {
    #expect(PaneLaunchChoice.builtins == [.shell, .pi, .codex, .claude])
    #expect(PaneLaunchChoice.builtins.map(\.title) == ["shell", "pi", "codex", "claude"])
  }

  @Test("builtins map to commands except shell")
  func builtinsMapToCommands() {
    #expect(PaneLaunchChoice.shell.command == nil)
    #expect(PaneLaunchChoice.pi.command == "pi")
    #expect(PaneLaunchChoice.codex.command == "codex")
    #expect(PaneLaunchChoice.claude.command == "claude")
  }

  @Test("custom request trims commands")
  func customRequestTrimsCommand() throws {
    let request = try #require(PaneLaunchRequest(action: .splitRight, customCommandText: " lazygit "))

    #expect(request.command == "lazygit")
    #expect(request.choice == .custom("lazygit"))
  }

  @Test("blank custom command does not create a request")
  func blankCustomCommandDoesNotCreateRequest() {
    #expect(PaneLaunchRequest(action: .newTab, customCommandText: "  \t ") == nil)
  }

  @Test("new tab request can carry a selected local cwd")
  func newTabRequestCanCarrySelectedLocalCwd() {
    let cwd = URL(fileURLWithPath: "/Users/alice/src/smoovmux")
    let request = PaneLaunchRequest(action: .newTab, choice: .shell, cwd: cwd)

    #expect(request.cwd == cwd)
  }

  @Test("recent paths move selected path to front and deduplicate")
  func recentPathsMoveSelectedPathToFrontAndDeduplicate() {
    let first = URL(fileURLWithPath: "/repo/first")
    let second = URL(fileURLWithPath: "/repo/second")
    let third = URL(fileURLWithPath: "/repo/third")

    #expect(
      PaneLauncherRecentPaths.updatedRecents(
        current: [first, second],
        selected: third,
        limit: 2
      ) == [third, first]
    )
    #expect(
      PaneLauncherRecentPaths.updatedRecents(
        current: [first, second],
        selected: second,
        limit: 3
      ) == [second, first]
    )
  }

  @Test("recent paths encode and decode path strings")
  func recentPathsEncodeAndDecodePathStrings() {
    let first = URL(fileURLWithPath: "/repo/first")
    let second = URL(fileURLWithPath: "/repo/second")

    #expect(PaneLauncherRecentPaths.pathStrings(for: [first, second]) == ["/repo/first", "/repo/second"])
    #expect(PaneLauncherRecentPaths.urls(for: ["/repo/first", "", "/repo/second"]) == [first, second])
  }
}
