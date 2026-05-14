import Testing

@testable import SessionCore

@Suite("Terminal copy policy")
struct TerminalCopyPolicyTests {
  @Test("cleaned copy strips Claude prompt and joins wrapped paragraphs")
  func cleanedCopyStripsClaudePromptAndJoinsWrappedParagraphs() {
    let policy = TerminalCopyPolicy()

    let input = """
      ❯ This is a long response that wrapped
      onto another terminal line.   

      ❯ A second paragraph keeps
      its paragraph break.
      """

    #expect(
      policy.cleaned(input) == """
        This is a long response that wrapped onto another terminal line.

        A second paragraph keeps its paragraph break.
        """
    )
  }

  @Test("cleaned copy leaves non Claude shell prompts untouched")
  func cleanedCopyLeavesNonClaudePromptsUntouched() {
    let policy = TerminalCopyPolicy()

    #expect(
      policy.cleaned("$ echo hello\n# root command\n> quoted text") == "$ echo hello # root command > quoted text")
  }

  @Test("cleaned copy keeps markdown fences and reconstructs wrapped code lines")
  func cleanedCopyKeepsMarkdownFencesAndReconstructsWrappedCodeLines() {
    let policy = TerminalCopyPolicy()

    let input = """
      ```bash
      : \\
      "this-is-a-long-token-00
      00000000000000000000" \\
      "yet-another-long-token-sti
      ll-complete" 
      ```
      """

    #expect(
      policy.cleaned(input) == """
        ```bash
        : \\
        "this-is-a-long-token-0000000000000000000000" \\
        "yet-another-long-token-still-complete"
        ```
        """
    )
  }

  @Test("copy mode defaults to cleanup and can be disabled")
  func copyModeDefaultsToCleanupAndCanBeDisabled() {
    #expect(TerminalCopyPolicy.mode(cleanupEnabled: true) == .cleaned)
    #expect(TerminalCopyPolicy.mode(cleanupEnabled: false) == .raw)
  }
}
