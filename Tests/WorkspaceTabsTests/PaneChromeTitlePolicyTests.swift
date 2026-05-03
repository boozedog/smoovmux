import Foundation
import Testing
import WorkspaceTabs

@Suite("Pane chrome title policy")
struct PaneChromeTitlePolicyTests {
  @Test("shell panes without terminal title show login shell executable")
  func shellPanesWithoutTerminalTitleShowLoginShellExecutable() {
    let title = PaneChromeTitlePolicy.title(
      command: nil,
      terminalTitle: nil,
      loginShellPath: "/run/current-system/sw/bin/fish"
    )

    #expect(title == "fish")
  }

  @Test("shell panes prefer live terminal title")
  func shellPanesPreferLiveTerminalTitle() {
    let title = PaneChromeTitlePolicy.title(
      command: nil,
      terminalTitle: "btop",
      loginShellPath: "/run/current-system/sw/bin/fish"
    )

    #expect(title == "btop")
  }

  @Test("command panes prefer live terminal title")
  func commandPanesPreferLiveTerminalTitle() {
    let title = PaneChromeTitlePolicy.title(
      command: "pi --model test",
      terminalTitle: "smoovmux issue #45",
      loginShellPath: "/bin/zsh"
    )

    #expect(title == "smoovmux issue #45")
  }

  @Test("command panes fall back to command basename")
  func commandPanesFallBackToCommandBasename() {
    let title = PaneChromeTitlePolicy.title(
      command: "/opt/homebrew/bin/lazygit --path .",
      terminalTitle: nil,
      loginShellPath: "/bin/zsh"
    )

    #expect(title == "lazygit")
  }

  @Test("blank terminal titles are ignored")
  func blankTerminalTitlesAreIgnored() {
    let title = PaneChromeTitlePolicy.title(
      command: "claude",
      terminalTitle: "  \n",
      loginShellPath: "/bin/zsh"
    )

    #expect(title == "claude")
  }

  @Test("chrome state renders the focused pane values")
  func chromeStateRendersFocusedPaneValues() {
    let state = PaneChromeState(
      command: "/opt/homebrew/bin/pi --model test",
      terminalTitle: "smoovmux issue #45",
      cwd: URL(fileURLWithPath: "/Users/alice/src/smoovmux")
    )

    #expect(state.title(loginShellPath: "/bin/zsh") == "smoovmux issue #45")
    #expect(state.cwdDisplay(homePath: "/Users/alice") == "~/src/smoovmux")
    #expect(state.commandKind(loginShellPath: "/bin/zsh") == "pi")
  }

  @Test("chrome state strips terminal title cwd suffix already shown separately")
  func chromeStateStripsDuplicateCwdSuffix() {
    let state = PaneChromeState(
      command: nil,
      terminalTitle: "trip racknerd-dfw ~",
      cwd: URL(fileURLWithPath: "/Users/alice")
    )

    #expect(state.title(loginShellPath: "/opt/homebrew/bin/fish", homePath: "/Users/alice") == "trip racknerd-dfw")
  }

  @Test("cwd display abbreviates home")
  func cwdDisplayAbbreviatesHome() {
    let cwd = URL(fileURLWithPath: "/Users/alice/src/smoovmux")

    #expect(PaneChromeTitlePolicy.cwdDisplay(cwd: cwd, homePath: "/Users/alice") == "~/src/smoovmux")
    #expect(PaneChromeTitlePolicy.cwdDisplay(cwd: nil, homePath: "/Users/alice") == "~")
  }
}
