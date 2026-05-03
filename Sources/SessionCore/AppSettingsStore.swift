import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
  public var defaultShellPath: String?

  public init(defaultShellPath: String? = nil) {
    self.defaultShellPath = defaultShellPath
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
