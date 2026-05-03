import Foundation

public enum TerminalExternalActionPolicy {
  public static func string(from pointer: UnsafePointer<UInt8>?, length: Int) -> String? {
    guard let pointer, length > 0 else { return nil }
    let buffer = UnsafeBufferPointer(start: pointer, count: length)
    return String(bytes: buffer, encoding: .utf8)
  }

  public static func openURL(from value: String?) -> URL? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
    guard ["https", "http", "mailto"].contains(scheme) else { return nil }
    return url
  }
}
