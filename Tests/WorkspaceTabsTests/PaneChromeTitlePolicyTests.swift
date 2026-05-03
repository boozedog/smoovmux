import Foundation
import Testing
import WorkspaceTabs

@Suite("Pane chrome title policy")
struct PaneChromeTitlePolicyTests {
  @Test("shell panes show login shell executable")
  func shellPanesShowLoginShellExecutable() {
    let title = PaneChromeTitlePolicy.title(
      command: nil,
      terminalTitle: "ignored",
      loginShellPath: "/run/current-system/sw/bin/fish"
    )

    #expect(title == "fish")
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

  @Test("cwd display abbreviates home")
  func cwdDisplayAbbreviatesHome() {
    let cwd = URL(fileURLWithPath: "/Users/alice/src/smoovmux")

    #expect(PaneChromeTitlePolicy.cwdDisplay(cwd: cwd, homePath: "/Users/alice") == "~/src/smoovmux")
    #expect(PaneChromeTitlePolicy.cwdDisplay(cwd: nil, homePath: "/Users/alice") == "~")
  }
}
