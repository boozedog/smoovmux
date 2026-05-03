public struct SettingsConfigSummaryRow: Equatable, Sendable {
  public let label: String
  public let value: String

  public init(label: String, value: String) {
    self.label = label
    self.value = value
  }
}

public struct SettingsConfigSummary: Equatable, Sendable {
  public let configPath: String
  public let fontFamily: String
  public let fontSize: String
  public let background: String
  public let foreground: String

  public init(configPath: String, configText: String, fallbackFontFamily: String) {
    let values = GhosttyConfigKeyValueParser.parse(configText)
    self.configPath = configPath
    self.fontFamily = values["font-family"] ?? fallbackFontFamily
    self.fontSize = values["font-size"] ?? "Default"
    self.background = values["background"] ?? "Default"
    self.foreground = values["foreground"] ?? "Default"
  }

  public var terminalRows: [SettingsConfigSummaryRow] {
    [
      SettingsConfigSummaryRow(label: "Font", value: fontFamily),
      SettingsConfigSummaryRow(label: "Font size", value: fontSize),
      SettingsConfigSummaryRow(label: "Background", value: background),
      SettingsConfigSummaryRow(label: "Foreground", value: foreground),
      SettingsConfigSummaryRow(label: "Config", value: configPath),
    ]
  }
}

enum GhosttyConfigKeyValueParser {
  static func parse(_ text: String) -> [String: String] {
    var values: [String: String] = [:]
    for rawLine in text.split(whereSeparator: \.isNewline) {
      let rawLine = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !rawLine.isEmpty, !rawLine.hasPrefix("#"), let equals = rawLine.firstIndex(of: "=") else { continue }
      let key = rawLine[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
      let rawValue = rawLine[rawLine.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
      let value = stripValueComment(String(rawValue)).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty, !value.isEmpty else { continue }
      values[String(key)] = String(value)
    }
    return values
  }

  private static func stripValueComment(_ value: String) -> String {
    guard !value.hasPrefix("#"), let hash = value.firstIndex(of: "#") else { return value }
    return String(value[..<hash])
  }
}
