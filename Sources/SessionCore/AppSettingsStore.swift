import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
  public var defaultShellPath: String?
  public var defaultLauncherKind: String?
  public var defaultLauncherCustomCommand: String?
  public var defaultWorkingDirectoryPath: String?
  public var cleanCopiedTerminalText: Bool

  public init(
    defaultShellPath: String? = nil,
    defaultLauncherKind: String? = nil,
    defaultLauncherCustomCommand: String? = nil,
    defaultWorkingDirectoryPath: String? = nil,
    cleanCopiedTerminalText: Bool = true
  ) {
    self.defaultShellPath = defaultShellPath
    self.defaultLauncherKind = defaultLauncherKind
    self.defaultLauncherCustomCommand = defaultLauncherCustomCommand
    self.defaultWorkingDirectoryPath = defaultWorkingDirectoryPath
    self.cleanCopiedTerminalText = cleanCopiedTerminalText
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    defaultShellPath = try container.decodeIfPresent(String.self, forKey: .defaultShellPath)
    defaultLauncherKind = try container.decodeIfPresent(String.self, forKey: .defaultLauncherKind)
    defaultLauncherCustomCommand = try container.decodeIfPresent(String.self, forKey: .defaultLauncherCustomCommand)
    defaultWorkingDirectoryPath = try container.decodeIfPresent(String.self, forKey: .defaultWorkingDirectoryPath)
    cleanCopiedTerminalText = try container.decodeIfPresent(Bool.self, forKey: .cleanCopiedTerminalText) ?? true
  }
}

public struct AppSettingsStore: Sendable {
  public static let defaultSettingsURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/smoovmux", isDirectory: true)
    .appendingPathComponent("settings.json")

  public let settingsURL: URL

  public init(settingsURL: URL = Self.defaultSettingsURL) {
    self.settingsURL = settingsURL
  }

  public func load() throws -> AppSettings {
    do {
      let data = try Data(contentsOf: settingsURL)
      return try JSONDecoder().decode(AppSettings.self, from: data)
    } catch CocoaError.fileReadNoSuchFile {
      return AppSettings()
    } catch DecodingError.dataCorrupted,
      DecodingError.keyNotFound,
      DecodingError.typeMismatch,
      DecodingError.valueNotFound
    {
      return AppSettings()
    }
  }

  public func save(_ settings: AppSettings) throws {
    try FileManager.default.createDirectory(
      at: settingsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(settings)
    try data.write(to: settingsURL, options: [.atomic])
  }
}
