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

public final class DefaultShellSettings {
  public static let defaultKey = "defaultShellPath"

  private let defaults: UserDefaults
  private let key: String

  public init(defaults: UserDefaults = .standard, key: String = DefaultShellSettings.defaultKey) {
    self.defaults = defaults
    self.key = key
  }

  public var storedShellPath: String? {
    get {
      defaults.string(forKey: key)
    }
    set {
      guard let newValue, !newValue.isEmpty else {
        defaults.removeObject(forKey: key)
        return
      }
      defaults.set(newValue, forKey: key)
    }
  }

  public var launchCommand: String? {
    DefaultShellPolicy.launchCommand(forStoredShellPath: storedShellPath)
  }
}
