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
}
