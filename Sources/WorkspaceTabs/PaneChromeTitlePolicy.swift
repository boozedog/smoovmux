import Foundation

public enum PaneChromeTitlePolicy {
  public static func title(command: String?, terminalTitle: String?, loginShellPath: String) -> String {
    guard let command else {
      return executableName(fromPath: loginShellPath, fallback: "shell")
    }

    if let terminalTitle = terminalTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !terminalTitle.isEmpty {
      return terminalTitle
    }

    return commandName(command)
  }

  public static func cwdDisplay(cwd: URL?, homePath: String) -> String {
    guard let path = cwd?.path else { return "~" }
    guard path.hasPrefix(homePath) else { return path }
    return "~" + path.dropFirst(homePath.count)
  }

  public static func commandName(_ command: String) -> String {
    let firstToken = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? command
    return executableName(fromPath: firstToken, fallback: command)
  }

  public static func executableName(fromPath path: String, fallback: String) -> String {
    let basename = URL(fileURLWithPath: path).lastPathComponent
    return basename.isEmpty ? fallback : basename
  }
}
