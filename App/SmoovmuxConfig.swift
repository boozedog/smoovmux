import Foundation

enum SmoovmuxConfig {
  static let directoryURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/smoovmux", isDirectory: true)
  static let configURL = directoryURL.appendingPathComponent("config")

  static let bundledDefaultConfigName = "smoovmux-default-ghostty"
  static let terminalFontFamily = AppFonts.familyName
}
