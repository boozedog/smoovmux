import Darwin
import Foundation

/// Logging facade. Bytes-in-terminal are PII-grade; never log pane bytes.
/// See CLAUDE.md § Privacy.
public enum SmoovLog {
  /// One-shot call so stderr is line-buffered when it's a redirected file
  /// (e.g. `reload.sh`'s `--stderr`). Default block-buffering loses the
  /// last few log lines when the process aborts before normal exit.
  private static let setupBuffering: Void = {
    setlinebuf(stderr)
  }()

  public static func info(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
    emit("INFO", message(), file: file, line: line)
  }

  public static func warn(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
    emit("WARN", message(), file: file, line: line)
  }

  public static func error(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
    emit("ERROR", message(), file: file, line: line)
  }

  private static func emit(_ level: String, _ message: String, file: String, line: Int) {
    _ = Self.setupBuffering
    FileHandle.standardError.write(Data("[\(level)] \(file):\(line) \(message)\n".utf8))
  }
}

/// Redact sensitive substrings from a string before logging.
/// Current policy: aliases OK, hostnames/usernames/keys must be redacted by the caller.
public func redact(_ s: String) -> String {
  // Placeholder — expand as SSH config handling lands.
  s.replacingOccurrences(
    of: #"(?i)(password|token|secret|key)=[^\s]+"#,
    with: "$1=<redacted>",
    options: .regularExpression)
}
