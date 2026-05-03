public enum TerminalClipboardKind: Sendable, Equatable {
  case standard
  case selection
  case primary
  case unknown(Int)
}

public enum TerminalClipboardRequestKind: Sendable, Equatable {
  case paste
  case osc52Read
  case osc52Write
  case unknown(Int)
}

public enum TerminalClipboardPolicy {
  public static func kind(rawValue: Int) -> TerminalClipboardKind {
    switch rawValue {
    case 0: return .standard
    case 1: return .selection
    case 2: return .primary
    default: return .unknown(rawValue)
    }
  }

  public static func requestKind(rawValue: Int) -> TerminalClipboardRequestKind {
    switch rawValue {
    case 0: return .paste
    case 1: return .osc52Read
    case 2: return .osc52Write
    default: return .unknown(rawValue)
    }
  }

  public static func allowsRead(kind: TerminalClipboardKind, request: TerminalClipboardRequestKind) -> Bool {
    switch (kind, request) {
    case (.standard, .paste):
      return true
    default:
      return false
    }
  }

  public static func allowsWrite(kind: TerminalClipboardKind, request: TerminalClipboardRequestKind, confirmed: Bool)
    -> Bool
  {
    switch (kind, request, confirmed) {
    case (.standard, .osc52Write, true):
      return true
    default:
      return false
    }
  }
}
