import Darwin
import Foundation
import SmoovLog

/// Resolves external binaries (`ssh`, `git`, `lazygit`, login shell)
/// against the user's interactive-shell `PATH`, not launchd's minimal one.
///
/// Resolution order for a given binary `name`:
///
///   1. **Explicit override** — a path supplied by settings (`ssh.path`,
///      `git.path`, ...). If the override is non-empty it is used verbatim;
///      the resolver refuses to fall through when an override is set but
///      unusable, so the user sees a clear error instead of silent fallback.
///   2. **Login-shell PATH** — `$SHELL -l -c 'printf %s "$PATH"'` is run once
///      per app session and the result is cached. Each directory is walked in
///      order looking for a regular file that's executable by us.
///   3. **Fallback path** — an app-supplied default. Only consulted if the
///      PATH search turned up nothing.
///
/// Setting `SMOOVMUX_DEBUG_PATH=1` in the environment emits a log line for
/// every resolution so users can diagnose why a binary was picked.
///
/// The login-shell PATH is memoized for the lifetime of the process. Changing
/// `$SHELL` or the user's rc files requires relaunching smoovmux.
public enum BinaryResolver {
  public enum ResolveError: Error, Equatable {
    /// No candidate produced a usable binary.
    case notFound(name: String)
    /// A candidate path existed but was not a regular, executable file.
    case notExecutable(path: String)
  }

  /// Memoized `PATH` as reported by the user's login shell. `nil` when the
  /// shell failed to launch, timed out, exited non-zero, or produced no
  /// output — callers should still fall back to `fallbackPATH`.
  public static let loginShellPATH: String? = detectLoginShellPATH()

  /// Hardcoded fallback used when the login shell couldn't produce a `PATH`.
  /// Covers Nix (single- and multi-user), Homebrew on both architectures, and
  /// the system defaults.
  public static let fallbackPATH: String = {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    return [
      "\(home)/.nix-profile/bin",
      "/run/current-system/sw/bin",
      "/nix/var/nix/profiles/default/bin",
      "/opt/homebrew/bin",
      "/opt/homebrew/sbin",
      "/usr/local/bin",
      "/usr/local/sbin",
      "\(home)/.local/bin",
      "\(home)/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin",
    ].joined(separator: ":")
  }()

  /// Ordered, de-duplicated list of directories to search. Login-shell `PATH`
  /// first when available, then the hardcoded fallback.
  public static func pathComponents() -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for source in [loginShellPATH, fallbackPATH] {
      guard let source else { continue }
      for part in source.split(separator: ":", omittingEmptySubsequences: true) {
        let dir = String(part)
        if seen.insert(dir).inserted {
          result.append(dir)
        }
      }
    }
    return result
  }

  /// Resolve `name` to an executable file URL.
  ///
  /// - Parameters:
  ///   - name: Binary basename (e.g. `"ssh"`).
  ///   - override: User-supplied absolute path. When non-nil and non-empty
  ///     the resolver refuses to fall back — unusable overrides throw
  ///     `.notExecutable`.
  ///   - fallback: Absolute path consulted last, after the PATH search. Used
  ///     for app-provided helpers.
  public static func resolve(
    _ name: String,
    override: String? = nil,
    fallback: String? = nil
  ) throws -> URL {
    if let override, !override.isEmpty {
      if isExecutableRegularFile(override) {
        logResolution(name, path: override, source: "override")
        return URL(fileURLWithPath: override)
      }
      logResolution(name, path: override, source: "override (not executable)")
      throw ResolveError.notExecutable(path: override)
    }

    for dir in pathComponents() {
      let candidate = "\(dir)/\(name)"
      if isExecutableRegularFile(candidate) {
        logResolution(name, path: candidate, source: "PATH")
        return URL(fileURLWithPath: candidate)
      }
    }

    if let fallback, !fallback.isEmpty, isExecutableRegularFile(fallback) {
      logResolution(name, path: fallback, source: "fallback")
      return URL(fileURLWithPath: fallback)
    }

    logResolution(name, path: nil, source: "not found")
    throw ResolveError.notFound(name: name)
  }

  // MARK: - Private

  private static let debugLoggingEnabled: Bool =
    ProcessInfo.processInfo.environment["SMOOVMUX_DEBUG_PATH"] == "1"

  private static func isExecutableRegularFile(_ path: String) -> Bool {
    var st = stat()
    guard stat(path, &st) == 0 else { return false }
    guard (st.st_mode & S_IFMT) == S_IFREG else { return false }
    return access(path, X_OK) == 0
  }

  private static func logResolution(_ name: String, path: String?, source: String) {
    guard debugLoggingEnabled else { return }
    if let path {
      SmoovLog.info("BinaryResolver: \(name) → \(path) [\(source)]")
    } else {
      SmoovLog.info("BinaryResolver: \(name) → (\(source))")
    }
  }

  private static func detectLoginShellPATH() -> String? {
    let env = ProcessInfo.processInfo.environment
    let shell = env["SHELL"] ?? "/bin/zsh"
    guard isExecutableRegularFile(shell) else {
      SmoovLog.warn("BinaryResolver: $SHELL (\(shell)) is not executable; using fallback PATH")
      return nil
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    process.standardInput = nil

    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }

    do {
      try process.run()
    } catch {
      SmoovLog.warn("BinaryResolver: failed to launch login shell \(shell): \(error)")
      return nil
    }

    // Bound total time so a wedged rc file doesn't block app startup.
    if exited.wait(timeout: .now() + .seconds(3)) == .timedOut {
      process.terminate()
      _ = exited.wait(timeout: .now() + .seconds(1))
      SmoovLog.warn("BinaryResolver: login shell timed out after 3s; using fallback PATH")
      return nil
    }

    guard process.terminationStatus == 0 else {
      SmoovLog.warn(
        "BinaryResolver: login shell \(shell) exited \(process.terminationStatus); using fallback PATH"
      )
      return nil
    }

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    let value = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value, !value.isEmpty else { return nil }
    return value
  }
}
