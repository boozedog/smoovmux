import Testing

@testable import SessionCore

@Suite("Settings config summary")
struct SettingsConfigSummaryTests {
  @Test("parses visible Ghostty config keys")
  func parsesVisibleGhosttyConfigKeys() {
    let summary = SettingsConfigSummary(
      configPath: "/Users/alice/.config/smoovmux/config",
      configText: """
        # comment
        font-family = Maple Mono NL NF
        font-size = 14
        background = #000000
        foreground = #f8f8f2
        """,
      fallbackFontFamily: "System"
    )

    #expect(summary.fontFamily == "Maple Mono NL NF")
    #expect(summary.fontSize == "14")
    #expect(summary.background == "#000000")
    #expect(summary.foreground == "#f8f8f2")
    #expect(summary.configPath == "/Users/alice/.config/smoovmux/config")
  }

  @Test("uses fallback font and unset placeholders")
  func usesFallbackFontAndUnsetPlaceholders() {
    let summary = SettingsConfigSummary(
      configPath: "/tmp/config",
      configText: "",
      fallbackFontFamily: "Maple Mono NL NF"
    )

    #expect(summary.fontFamily == "Maple Mono NL NF")
    #expect(summary.fontSize == "Default")
    #expect(summary.background == "Default")
    #expect(summary.foreground == "Default")
  }

  @Test("last matching key wins and inline comments are trimmed")
  func lastMatchingKeyWins() {
    let summary = SettingsConfigSummary(
      configPath: "/tmp/config",
      configText: """
        font-family = First
        font-family = Second # inline comment
        font-size=13
        """,
      fallbackFontFamily: "Fallback"
    )

    #expect(summary.fontFamily == "Second")
    #expect(summary.fontSize == "13")
  }

  @Test("summary rows are stable and user visible")
  func summaryRowsAreStable() {
    let rows = SettingsConfigSummary(
      configPath: "/tmp/config",
      configText: "font-family = JetBrains Mono",
      fallbackFontFamily: "Fallback"
    ).terminalRows

    #expect(rows.map(\.label) == ["Font", "Font size", "Background", "Foreground", "Config"])
    #expect(rows.last?.value == "/tmp/config")
  }
}
