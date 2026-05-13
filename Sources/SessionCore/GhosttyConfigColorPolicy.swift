import Foundation

public enum GhosttyConfigColorPolicy {
  public static func hexColor(named key: String, in configText: String) -> Int? {
    for rawLine in configText.components(separatedBy: .newlines).reversed() {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.hasPrefix("#") else { continue }
      let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      guard parts.count == 2, parts[0] == key else { continue }
      let rawValue = parts[1].components(separatedBy: .whitespaces).first ?? parts[1]
      return hexColor(from: rawValue)
    }
    return nil
  }

  public static func hexColor(from rawValue: String) -> Int? {
    let hex = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "# \t"))
    guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
    return value
  }
}
