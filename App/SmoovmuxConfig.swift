import Foundation

enum SmoovmuxConfig {
  static let directoryURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/smoovmux", isDirectory: true)
  static let configURL = directoryURL.appendingPathComponent("config")

  static let bundledDefaultConfigName = "smoovmux-default-ghostty"
  static let terminalFontFamily = AppFonts.familyName

  static var defaultConfigText: String {
    guard
      let url = Bundle.main.url(forResource: bundledDefaultConfigName, withExtension: nil),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      return "font-family = \(terminalFontFamily)\n"
    }
    return text
  }
}
