import AppKit
import Foundation

enum GhosttyConfigColors {
  static var dividerColor: NSColor {
    guard let background = configuredColor(named: "background") else {
      return NSColor.separatorColor.withAlphaComponent(0.55)
    }
    return background.blended(withFraction: 0.18, of: .white) ?? NSColor.separatorColor.withAlphaComponent(0.55)
  }

  private static func configuredColor(named key: String) -> NSColor? {
    let configURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/ghostty/config")
    guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }

    for rawLine in contents.components(separatedBy: .newlines).reversed() {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.hasPrefix("#") else { continue }
      let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      guard parts.count == 2, parts[0] == key else { continue }
      return color(from: parts[1].components(separatedBy: .whitespaces).first ?? parts[1])
    }
    return nil
  }

  private static func color(from rawValue: String) -> NSColor? {
    let hex = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "# \t"))
    guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
    return NSColor(
      red: CGFloat((value >> 16) & 0xff) / 255.0,
      green: CGFloat((value >> 8) & 0xff) / 255.0,
      blue: CGFloat(value & 0xff) / 255.0,
      alpha: 1.0
    )
  }
}
