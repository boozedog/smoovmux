import Foundation

public enum PaneLaunchAction: Equatable, Sendable {
  case newTab
  case splitRight
  case splitDown
}

public enum PaneLaunchChoice: Equatable, Sendable {
  case shell
  case pi
  case codex
  case claude
  case custom(String)

  public var title: String {
    switch self {
    case .shell:
      return "shell"
    case .pi:
      return "pi"
    case .codex:
      return "codex"
    case .claude:
      return "claude"
    case .custom:
      return "enter a command…"
    }
  }

  public var command: String? {
    switch self {
    case .shell:
      return nil
    case .pi:
      return "pi"
    case .codex:
      return "codex"
    case .claude:
      return "claude"
    case .custom(let command):
      return command
    }
  }

  public static let builtins: [Self] = [.shell, .pi, .codex, .claude]
}

public enum PaneLauncherNavigationMode: Equatable, Sendable {
  case list
  case custom
}

public enum PaneLauncherNavigationKey: Equatable, Sendable {
  case up
  case down
  case enter
  case escape
  case number(Int)
}

public enum PaneLauncherNavigationIntent: Equatable, Sendable {
  case pick(index: Int)
  case launchShell
  case launchCustom
}

public struct PaneLauncherNavigationState: Equatable, Sendable {
  public var rowCount: Int
  public var selectedIndex: Int
  public var mode: PaneLauncherNavigationMode

  public init(rowCount: Int, selectedIndex: Int = 0, mode: PaneLauncherNavigationMode = .list) {
    self.rowCount = max(1, rowCount)
    self.selectedIndex = min(max(0, selectedIndex), self.rowCount - 1)
    self.mode = mode
  }

  public mutating func handle(_ key: PaneLauncherNavigationKey) -> PaneLauncherNavigationIntent? {
    switch (mode, key) {
    case (.list, .up):
      selectedIndex = (selectedIndex - 1 + rowCount) % rowCount
      return nil
    case (.list, .down):
      selectedIndex = (selectedIndex + 1) % rowCount
      return nil
    case (.list, .enter):
      return .pick(index: selectedIndex)
    case (.list, .escape):
      return .launchShell
    case (.list, .number(let value)) where value >= 1 && value <= rowCount:
      selectedIndex = value - 1
      return .pick(index: selectedIndex)
    case (.custom, .escape):
      mode = .list
      return nil
    case (.custom, .enter):
      return .launchCustom
    default:
      return nil
    }
  }
}

public struct PaneLaunchRequest: Equatable, Sendable {
  public var action: PaneLaunchAction
  public var choice: PaneLaunchChoice

  public var command: String? {
    choice.command
  }

  public init(action: PaneLaunchAction, choice: PaneLaunchChoice) {
    self.action = action
    self.choice = choice
  }

  public init?(action: PaneLaunchAction, customCommandText: String) {
    let trimmed = customCommandText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    self.init(action: action, choice: .custom(trimmed))
  }
}
