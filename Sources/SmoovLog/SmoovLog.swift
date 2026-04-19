import Foundation

/// Logging facade. Bytes-in-terminal are PII-grade; never log pane bytes.
/// See CLAUDE.md § Privacy.
public enum SmoovLog {
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
		FileHandle.standardError.write(Data("[\(level)] \(file):\(line) \(message)\n".utf8))
	}
}

/// Redact sensitive substrings from a string before logging.
/// Current policy: aliases OK, hostnames/usernames/keys must be redacted by the caller.
public func redact(_ s: String) -> String {
	// Placeholder — expand as SSH config handling lands.
	s.replacingOccurrences(of: #"(?i)(password|token|secret|key)=[^\s]+"#,
		with: "$1=<redacted>",
		options: .regularExpression)
}
