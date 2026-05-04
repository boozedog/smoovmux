import Foundation

public enum DefaultLauncherChoice: Equatable, Sendable {
  case shell
  case pi
  case codex
  case claude
  case custom(command: String)

  public var id: String {
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
      return "custom"
    }
  }

  public var title: String {
    switch self {
    case .shell:
      return "Shell"
    case .pi:
      return "pi"
    case .codex:
      return "codex"
    case .claude:
      return "claude"
    case .custom:
      return "Enter a command…"
    }
  }

  public var customCommand: String? {
    if case .custom(let command) = self {
      return command
    }
    return nil
  }

  public static let options: [Self] = [.shell, .pi, .codex, .claude, .custom(command: "")]

  public static func choice(kind: String?, customCommand: String?) -> Self {
    switch kind {
    case "pi":
      return .pi
    case "codex":
      return .codex
    case "claude":
      return .claude
    case "custom":
      let trimmed = (customCommand ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return .shell }
      return .custom(command: trimmed)
    default:
      return .shell
    }
  }
}

public struct DefaultLauncherSettings: Sendable {
  private let store: AppSettingsStore

  public init(store: AppSettingsStore = AppSettingsStore()) {
    self.store = store
  }

  public var choice: DefaultLauncherChoice {
    get {
      let settings = (try? store.load()) ?? AppSettings()
      return DefaultLauncherChoice.choice(
        kind: settings.defaultLauncherKind,
        customCommand: settings.defaultLauncherCustomCommand
      )
    }
    nonmutating set {
      var settings = (try? store.load()) ?? AppSettings()
      settings.defaultLauncherKind = newValue.id
      settings.defaultLauncherCustomCommand = newValue.customCommand
      try? store.save(settings)
    }
  }
}
