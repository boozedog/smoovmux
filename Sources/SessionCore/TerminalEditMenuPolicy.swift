public enum TerminalEditMenuAction: Sendable, Equatable {
  case copy
  case copyRaw
  case paste
}

public struct TerminalEditMenuItem: Sendable, Equatable {
  public let action: TerminalEditMenuAction
  public let title: String
  public let isEnabled: Bool

  public init(action: TerminalEditMenuAction, title: String, isEnabled: Bool) {
    self.action = action
    self.title = title
    self.isEnabled = isEnabled
  }
}

public enum TerminalEditMenuPolicy {
  public static func items(hasSelection: Bool, canPaste: Bool) -> [TerminalEditMenuItem] {
    [
      TerminalEditMenuItem(action: .copy, title: "Copy", isEnabled: hasSelection),
      TerminalEditMenuItem(action: .copyRaw, title: "Copy Without Cleanup", isEnabled: hasSelection),
      TerminalEditMenuItem(action: .paste, title: "Paste", isEnabled: canPaste),
    ]
  }
}
