import Foundation

public enum PaneLaunchAction: Equatable, Sendable {
  case newTab
  case splitRight
  case splitDown
}

public enum PaneLaunchChoice: Equatable, Sendable {
  case pi
  case claude
  case hermes
  case shell
  case custom(String)

  public var title: String {
    switch self {
    case .pi:
      return "pi"
    case .claude:
      return "claude"
    case .hermes:
      return "hermes"
    case .shell:
      return "shell"
    case .custom:
      return "enter a command…"
    }
  }

  public var command: String? {
    switch self {
    case .pi:
      return "pi"
    case .claude:
      return "claude"
    case .hermes:
      return "hermes"
    case .shell:
      return nil
    case .custom(let command):
      return command
    }
  }

  public static let builtins: [Self] = [.pi, .claude, .hermes, .shell]
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
