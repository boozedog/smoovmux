import Darwin
import Foundation
import SmoovLog
import TmuxCC

/// Spawns a local tmux server in `-C` control mode under a PTY and wires it
/// to a `TmuxGateway`. Each smoovmux window gets its own tmux socket keyed by
/// `windowId`, so we never touch the user's default tmux. `-A` on
/// `new-session` makes attach-or-create idempotent.
///
/// Why `-C` and not `-CC`: `-CC` wraps the entire control stream in a DCS
/// string (`ESC P 1 0 0 0 p … ESC \`), which is what you want when tmux is
/// embedded inside another terminal emulator. We own the PTY, so we instead
/// take `-C` and disable ECHO on the slave tty before spawning — that gives
/// us a clean `%notification`/`%begin…%end` byte stream the parser can
/// consume directly, no DCS stripper required.
public enum LocalTmuxSession {
  /// Handle returned by `start`.
  ///
  /// `childExit` is the PTY child's exit stream (consume it to observe the
  /// tmux server terminating). `gateway.start()` has *not* been called yet —
  /// the caller owns the drain task so it can also observe `stateStream`.
  public struct Launch: Sendable {
    public let gateway: TmuxGateway
    public let childExit: AsyncStream<Int32>
    public let windowId: UUID
    public let socketLabel: String
    public let pid: pid_t
  }

  public enum LaunchError: Error {
    case tmuxNotFound(BinaryResolver.ResolveError)
    case spawnFailed(PTYError)
  }

  public static func start(
    tmuxOverride: String? = nil,
    bundledTmuxFallback: String? = nil,
    cwd: URL? = nil,
    cols: UInt16 = 80,
    rows: UInt16 = 24,
    windowId: UUID = UUID()
  ) throws -> Launch {
    let tmuxURL: URL
    do {
      tmuxURL = try BinaryResolver.resolve(
        "tmux", override: tmuxOverride, fallback: bundledTmuxFallback)
    } catch let error as BinaryResolver.ResolveError {
      throw LaunchError.tmuxNotFound(error)
    }

    let socketLabel = "smoovmux-\(windowId.uuidString.lowercased())"
    let arguments = ["-C", "-L", socketLabel, "new-session", "-A", "-s", "smoovmux"]
    let environment = buildEnvironment()

    let child: PTYChild
    do {
      child = try PTY.spawn(
        executable: tmuxURL,
        arguments: arguments,
        environment: environment,
        cwd: cwd,
        cols: cols,
        rows: rows
      )
    } catch let error as PTYError {
      throw LaunchError.spawnFailed(error)
    }

    // Non-blocking so the read source never parks a GCD worker inside read(2).
    let fd = child.pty.fileDescriptor
    let flags = fcntl(fd, F_GETFL)
    if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }

    // tmux `-C` (single) leaves the PTY in its default cooked mode, which
    // echoes every command we write back to us. The parser only accepts lines
    // starting with `%`, so the echoes look like protocol violations and
    // knock the parser into its broken state. Turn off ECHO (plus the other
    // line-discipline niceties we don't want) before tmux inherits the tty.
    disableEcho(fd: fd)

    let (input, inputCont) = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)

    let readQueue = DispatchQueue(label: "smoovmux.pty.read.\(child.pid)")
    let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
    readSource.setEventHandler {
      var buffer = [UInt8](repeating: 0, count: 4096)
      let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
        read(fd, ptr.baseAddress, ptr.count)
      }
      if bytesRead > 0 {
        inputCont.yield(Data(bytes: buffer, count: bytesRead))
      } else if bytesRead == 0 {
        inputCont.finish()
        readSource.cancel()
      } else {
        let code = errno
        if code != EAGAIN && code != EINTR {
          inputCont.finish()
          readSource.cancel()
        }
      }
    }
    readSource.resume()

    // Retain the PTY handle in the write closure so the master fd stays open
    // until the gateway itself is released.
    let ptyHandle = child.pty
    let gateway = TmuxGateway(input: input) { data in
      do {
        try ptyHandle.write(contentsOf: data)
      } catch {
        SmoovLog.warn("tmux PTY write failed: \(error)")
      }
    }

    return Launch(
      gateway: gateway,
      childExit: child.onExit,
      windowId: windowId,
      socketLabel: socketLabel,
      pid: child.pid
    )
  }

  // MARK: - Termios

  private static func disableEcho(fd: Int32) {
    var attrs = termios()
    guard tcgetattr(fd, &attrs) == 0 else { return }
    // Clear ECHO/ECHOE/ECHOK/ECHONL so neither our writes nor tmux's startup
    // writes are echoed back. ICANON stays on — tmux wants line-buffered
    // input on its control socket.
    let lflag = tcflag_t(ECHO | ECHOE | ECHOK | ECHONL)
    attrs.c_lflag &= ~lflag
    _ = tcsetattr(fd, TCSANOW, &attrs)
  }

  // MARK: - Environment

  /// Inherit the current process environment, then overlay a freshly-resolved
  /// login-shell `PATH` so child shells inside tmux see what the user sees in
  /// Terminal.app. Strip `TMUX*` so spawned tmux never thinks it's nested.
  private static func buildEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    // If we happen to run inside a tmux (devenv shell, tests under tmux,
    // etc.) tmux refuses to nest; strip the markers so our spawned tmux is
    // independent.
    env.removeValue(forKey: "TMUX")
    env.removeValue(forKey: "TMUX_PANE")

    let pathDirs = BinaryResolver.pathComponents()
    if !pathDirs.isEmpty {
      env["PATH"] = pathDirs.joined(separator: ":")
    }
    if env["TERM"] == nil {
      env["TERM"] = "xterm-256color"
    }
    return env
  }
}
