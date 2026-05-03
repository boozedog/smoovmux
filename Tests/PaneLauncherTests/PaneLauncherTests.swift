import PaneLauncher
import Testing

@Suite("Pane launcher policy")
struct PaneLauncherTests {
  @Test("builtins match the requested launcher order")
  func builtinsMatchRequestedLauncherOrder() {
    #expect(PaneLaunchChoice.builtins == [.pi, .claude, .hermes, .shell])
    #expect(PaneLaunchChoice.builtins.map(\.title) == ["pi", "claude", "hermes", "shell"])
  }

  @Test("builtins map to commands except shell")
  func builtinsMapToCommands() {
    #expect(PaneLaunchChoice.pi.command == "pi")
    #expect(PaneLaunchChoice.claude.command == "claude")
    #expect(PaneLaunchChoice.hermes.command == "hermes")
    #expect(PaneLaunchChoice.shell.command == nil)
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
