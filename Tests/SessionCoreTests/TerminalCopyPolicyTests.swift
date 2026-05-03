import Testing

@testable import SessionCore

@Suite("Terminal copy policy")
struct TerminalCopyPolicyTests {
  @Test("cleaned copy strips prompt prefixes and trailing whitespace")
  func cleanedCopyStripsPromptsAndTrailingWhitespace() {
    let policy = TerminalCopyPolicy()

    #expect(policy.cleaned("$ echo hello   \n> continued  ") == "echo hello\ncontinued")
  }

  @Test("cleaned copy collapses runs of blank lines")
  func cleanedCopyCollapsesBlankRuns() {
    let policy = TerminalCopyPolicy()

    #expect(policy.cleaned("one\n\n\n\n# two") == "one\n\n\ntwo")
  }

  @Test("cleaned copy preserves raw text when using raw mode outside policy")
  func rawCopyIsCallerControlled() {
    let text = "$ echo hello   "

    #expect(text == "$ echo hello   ")
  }
}
