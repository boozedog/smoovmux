import Testing

@testable import SessionCore

@Suite("Ghostty config color policy")
struct GhosttyConfigColorPolicyTests {
  @Test("reads the last split divider color from config")
  func readsLastSplitDividerColor() {
    let config = """
      split-divider-color = #111111
      background = #0d1117
      split-divider-color = #666666
      """

    #expect(GhosttyConfigColorPolicy.hexColor(named: "split-divider-color", in: config) == 0x666666)
  }

  @Test("ignores comments and inline whitespace")
  func ignoresCommentsAndWhitespace() {
    let config = """
      # split-divider-color = #111111
        split-divider-color = #666666   # comment
      """

    #expect(GhosttyConfigColorPolicy.hexColor(named: "split-divider-color", in: config) == 0x666666)
  }
}
