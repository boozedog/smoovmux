import Foundation

public struct PaneChromeState: Equatable, Sendable {
  public var command: String?
  public var terminalTitle: String?
  public var cwd: URL?

  public init(command: String? = nil, terminalTitle: String? = nil, cwd: URL? = nil) {
    self.command = command
    self.terminalTitle = terminalTitle
    self.cwd = cwd
  }

  public func title(loginShellPath: String, homePath: String? = nil) -> String {
    let title = PaneChromeTitlePolicy.title(
      command: command,
      terminalTitle: terminalTitle,
      loginShellPath: loginShellPath
    )
    guard let homePath else { return title }
    return PaneChromeTitlePolicy.strippingDuplicateCwdSuffix(
      from: title,
      cwd: cwd,
      homePath: homePath
    )
  }

  public func cwdDisplay(homePath: String) -> String {
    PaneChromeTitlePolicy.cwdDisplay(cwd: cwd, homePath: homePath)
  }

  public func commandKind(loginShellPath: String) -> String {
    guard let command else {
      return PaneChromeTitlePolicy.executableName(fromPath: loginShellPath, fallback: "shell")
    }
    return PaneChromeTitlePolicy.commandName(command)
  }
}

public enum PaneChromeTitlePolicy {
  public static func title(command: String?, terminalTitle: String?, loginShellPath: String) -> String {
    if let terminalTitle = terminalTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !terminalTitle.isEmpty {
      return terminalTitle
    }

    guard let command else {
      return executableName(fromPath: loginShellPath, fallback: "shell")
    }

    return commandName(command)
  }

  public static func cwdDisplay(cwd: URL?, homePath: String) -> String {
    guard let path = cwd?.path else { return "~" }
    guard path.hasPrefix(homePath) else { return path }
    return "~" + path.dropFirst(homePath.count)
  }

  public static func strippingDuplicateCwdSuffix(from title: String, cwd: URL?, homePath: String) -> String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty, let cwd else { return trimmedTitle }

    for suffix in duplicateCwdSuffixes(cwd: cwd, homePath: homePath) {
      guard trimmedTitle != suffix, trimmedTitle.hasSuffix(suffix) else { continue }
      let prefix = String(trimmedTitle.dropLast(suffix.count))
      guard prefix.last?.isWhitespace == true else { continue }
      let stripped = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
      if !stripped.isEmpty {
        return stripped
      }
    }

    return trimmedTitle
  }

  public static func commandName(_ command: String) -> String {
    let firstToken = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? command
    return executableName(fromPath: firstToken, fallback: command)
  }

  private static func duplicateCwdSuffixes(cwd: URL, homePath: String) -> [String] {
    var suffixes = [cwdDisplay(cwd: cwd, homePath: homePath), cwd.path]
    suffixes.removeAll { $0.isEmpty }
    return Array(Set(suffixes)).sorted { $0.count > $1.count }
  }

  public static func executableName(fromPath path: String, fallback: String) -> String {
    let basename = URL(fileURLWithPath: path).lastPathComponent
    return basename.isEmpty ? fallback : basename
  }
}
