import Darwin
import Foundation

public struct DefaultShellOption: Equatable, Identifiable, Sendable {
  public let id: String
  public let title: String
  public let shellPath: String?

  public init(id: String, title: String, shellPath: String?) {
    self.id = id
    self.title = title
    self.shellPath = shellPath
  }
}

public enum DefaultShellPolicy {
  public static let systemDefaultID = "system"

  public static func options(
    availableShellPaths: [String],
    systemDefaultShellPath: String
  ) -> [DefaultShellOption] {
    let systemTitle = "System default (\(systemDefaultShellPath))"
    let system = DefaultShellOption(id: systemDefaultID, title: systemTitle, shellPath: nil)
    let shells = availableShellPaths.map { path in
      DefaultShellOption(id: path, title: path, shellPath: path)
    }
    return [system] + shells
  }

  public static func availableShells(
    shellsFileText: String,
    isExecutableFile: (String) -> Bool
  ) -> [String] {
    var seen = Set<String>()
    var paths: [String] = []
    for line in shellsFileText.split(whereSeparator: \.isNewline) {
      let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !path.isEmpty, !path.hasPrefix("#"), path.hasPrefix("/"), isExecutableFile(path), seen.insert(path).inserted
      else { continue }
      paths.append(path)
    }
    return paths
  }

  public static func launchCommand(forStoredShellPath storedShellPath: String?) -> String? {
    guard let storedShellPath, !storedShellPath.isEmpty else { return nil }
    return storedShellPath
  }

  public static func systemDefaultShellPath(environment: [String: String] = ProcessInfo.processInfo.environment)
    -> String
  {
    environment["SHELL"] ?? "/bin/zsh"
  }

  public static func readAvailableShells(shellsFileURL: URL = URL(fileURLWithPath: "/etc/shells")) -> [String] {
    guard let text = try? String(contentsOf: shellsFileURL, encoding: .utf8) else { return [] }
    return availableShells(shellsFileText: text, isExecutableFile: isExecutableRegularFile(_:))
  }

  private static func isExecutableRegularFile(_ path: String) -> Bool {
    var statBuf = stat()
    guard stat(path, &statBuf) == 0 else { return false }
    guard (statBuf.st_mode & S_IFMT) == S_IFREG else { return false }
    return access(path, X_OK) == 0
  }
}

public struct DefaultShellSettings: Sendable {
  private let store: AppSettingsStore

  public init(store: AppSettingsStore = AppSettingsStore()) {
    self.store = store
  }

  public var storedShellPath: String? {
    get {
      try? store.load().defaultShellPath
    }
    nonmutating set {
      var settings = (try? store.load()) ?? AppSettings()
      settings.defaultShellPath = newValue?.isEmpty == true ? nil : newValue
      try? store.save(settings)
    }
  }

  public var launchCommand: String? {
    DefaultShellPolicy.launchCommand(forStoredShellPath: storedShellPath)
  }
}
