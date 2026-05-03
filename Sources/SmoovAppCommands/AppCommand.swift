public struct KeyboardShortcutModifiers: OptionSet, Equatable, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let command = Self(rawValue: 1 << 0)
  public static let shift = Self(rawValue: 1 << 1)
}

public struct KeyboardShortcutSpec: Equatable, Hashable, Sendable {
  public let key: String
  public let modifiers: KeyboardShortcutModifiers

  public init(key: String, modifiers: KeyboardShortcutModifiers) {
    self.key = key
    self.modifiers = modifiers
  }
}

public enum AppCommand: CaseIterable, Equatable, Sendable {
  case newWindow
  case newTab
  case closeTab
  case nextTab
  case previousTab
  case splitRight
  case splitDown
  case closePane
  case toggleRightSidebar

  public var title: String {
    switch self {
    case .newWindow:
      return "New Window"
    case .newTab:
      return "New Tab"
    case .closeTab:
      return "Close Tab"
    case .nextTab:
      return "Next Tab"
    case .previousTab:
      return "Previous Tab"
    case .splitRight:
      return "Split Right"
    case .splitDown:
      return "Split Down"
    case .closePane:
      return "Close Pane"
    case .toggleRightSidebar:
      return "Toggle Git Sidebar"
    }
  }

  public var shortcut: KeyboardShortcutSpec? {
    switch self {
    case .newWindow:
      return KeyboardShortcutSpec(key: "n", modifiers: [.command])
    case .newTab:
      return KeyboardShortcutSpec(key: "t", modifiers: [.command])
    case .closeTab:
      return nil
    case .nextTab:
      return KeyboardShortcutSpec(key: "]", modifiers: [.command])
    case .previousTab:
      return KeyboardShortcutSpec(key: "[", modifiers: [.command])
    case .splitRight:
      return KeyboardShortcutSpec(key: "d", modifiers: [.command])
    case .splitDown:
      return KeyboardShortcutSpec(key: "D", modifiers: [.command, .shift])
    case .closePane:
      return KeyboardShortcutSpec(key: "w", modifiers: [.command])
    case .toggleRightSidebar:
      return KeyboardShortcutSpec(key: "g", modifiers: [.command, .shift])
    }
  }
}
