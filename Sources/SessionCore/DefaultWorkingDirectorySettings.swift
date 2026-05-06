import Foundation

public enum DefaultWorkingDirectoryPolicy {
  public static func storedPath(
    from settings: AppSettings, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> String {
    let trimmed = settings.defaultWorkingDirectoryPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmed.isEmpty {
      return NSString(string: trimmed).expandingTildeInPath
    }
    return homeDirectory.appendingPathComponent("projects", isDirectory: true).path
  }

  public static func resolveTopLevelCwd(
    inheritedOrRestoredCwd: URL?,
    storedPath: String,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default
  ) -> URL {
    if let inheritedOrRestoredCwd {
      return inheritedOrRestoredCwd
    }

    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: storedPath, isDirectory: &isDirectory), isDirectory.boolValue {
      return URL(fileURLWithPath: storedPath, isDirectory: true)
    }
    return homeDirectory
  }
}

public struct DefaultWorkingDirectorySettings: Sendable {
  private let store: AppSettingsStore

  public init(store: AppSettingsStore = AppSettingsStore()) {
    self.store = store
  }

  public var storedPath: String {
    get {
      DefaultWorkingDirectoryPolicy.storedPath(from: (try? store.load()) ?? AppSettings())
    }
    nonmutating set {
      var settings = (try? store.load()) ?? AppSettings()
      let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      settings.defaultWorkingDirectoryPath = trimmed.isEmpty ? nil : trimmed
      try? store.save(settings)
    }
  }

  public func resolveTopLevelCwd(inheritedOrRestoredCwd: URL?) -> URL {
    DefaultWorkingDirectoryPolicy.resolveTopLevelCwd(
      inheritedOrRestoredCwd: inheritedOrRestoredCwd,
      storedPath: storedPath
    )
  }
}
