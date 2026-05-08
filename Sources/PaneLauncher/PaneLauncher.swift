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
  public var cwd: URL?

  public var command: String? {
    choice.command
  }

  public init(action: PaneLaunchAction, choice: PaneLaunchChoice, cwd: URL? = nil) {
    self.action = action
    self.choice = choice
    self.cwd = cwd
  }

  public init?(action: PaneLaunchAction, customCommandText: String, cwd: URL? = nil) {
    let trimmed = customCommandText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    self.init(action: action, choice: .custom(trimmed), cwd: cwd)
  }
}

public enum PaneLauncherRecentPaths {
  public static func updatedRecents(current: [URL], selected: URL?, limit: Int = 8) -> [URL] {
    guard let selected, limit > 0 else { return Array(current.prefix(max(0, limit))) }
    var result = [selected]
    result.append(contentsOf: current.filter { $0.standardizedFileURL != selected.standardizedFileURL })
    return Array(result.prefix(limit))
  }

  public static func pathStrings(for urls: [URL]) -> [String] {
    urls.map(\.path)
  }

  public static func urls(for pathStrings: [String]) -> [URL] {
    pathStrings.compactMap { path in
      guard !path.isEmpty else { return nil }
      return URL(fileURLWithPath: path)
    }
  }
}
