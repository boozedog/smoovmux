import Foundation

public enum TerminalTextInputPolicy {
  public static func keyText(composed: String?, fallback: String?) -> String? {
    if let composed, !composed.isEmpty { return composed }
    return textPayload(fallback)
  }

  public static func keyPayload(_ text: String?) -> String? {
    guard let text = textPayload(text), let firstByte = text.utf8.first, firstByte >= 0x20 else {
      return nil
    }
    return text
  }

  public static func insertionText(from value: Any) -> String? {
    switch value {
    case let text as String:
      return textPayload(text)
    case let text as NSAttributedString:
      return textPayload(text.string)
    default:
      return nil
    }
  }

  public static func textPayload(_ text: String?) -> String? {
    guard let text, !text.isEmpty else { return nil }
    return text
  }
}
