import Darwin
import Foundation

/// A spawned child process attached to a pseudo-terminal.
///
/// `pty` is the parent's end of the PTY pair (POSIX "master") — read child
/// output from it, write child input to it. It closes on deallocation, so
/// dropping the child sends EOF to its stdin. `onExit` yields the decoded exit
/// status exactly once and then finishes.
public struct PTYChild: Sendable {
  public let pid: pid_t
  public let pty: FileHandle
  public let onExit: AsyncStream<Int32>
}

public enum PTYError: Error, Equatable {
  case openpty(errno: Int32)
  case spawn(errno: Int32)
  case ioctl(errno: Int32)
}

/// Thin Swift wrapper around `openpty(3)` + `posix_spawn(2)` for spawning a
/// child process with a controlling pseudo-terminal. Shared by local tmux
/// (M1) and remote ssh (M5).
public enum PTY {
  /// Spawn `executable` under a fresh PTY pair. The child runs with `setsid`
  /// (so its end of the PTY becomes its controlling tty), default signal
  /// handlers, and an empty signal mask. `argv[0]` is set to `executable.path`.
  public static func spawn(  // swiftlint:disable:this function_parameter_count
    executable: URL,
    arguments: [String],
    environment: [String: String],
    cwd: URL?,
    cols: UInt16,
    rows: UInt16
  ) throws -> PTYChild {
    var controllerFD: Int32 = -1
    var childFD: Int32 = -1
    var ws = winsize()
    ws.ws_row = rows
    ws.ws_col = cols
    ws.ws_xpixel = 0
    ws.ws_ypixel = 0
    let openResult = withUnsafeMutablePointer(to: &ws) { wsPtr in
      openpty(&controllerFD, &childFD, nil, nil, wsPtr)
    }
    guard openResult == 0 else { throw PTYError.openpty(errno: errno) }

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, childFD, 0)
    posix_spawn_file_actions_adddup2(&actions, childFD, 1)
    posix_spawn_file_actions_adddup2(&actions, childFD, 2)
    posix_spawn_file_actions_addclose(&actions, childFD)
    posix_spawn_file_actions_addclose(&actions, controllerFD)
    if let cwd {
      _ = cwd.path.withCString { posix_spawn_file_actions_addchdir_np(&actions, $0) }
    }

    var attrs: posix_spawnattr_t?
    posix_spawnattr_init(&attrs)
    defer { posix_spawnattr_destroy(&attrs) }
    let flags = Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
    posix_spawnattr_setflags(&attrs, flags)
    var defaultSigs = sigset_t()
    sigfillset(&defaultSigs)
    posix_spawnattr_setsigdefault(&attrs, &defaultSigs)
    var maskSigs = sigset_t()
    sigemptyset(&maskSigs)
    posix_spawnattr_setsigmask(&attrs, &maskSigs)

    let argvCStrings: [UnsafeMutablePointer<CChar>?] =
      ([executable.path] + arguments).map { strdup($0) }
    defer { for ptr in argvCStrings { free(ptr) } }
    let envCStrings: [UnsafeMutablePointer<CChar>?] =
      environment.map { strdup("\($0.key)=\($0.value)") }
    defer { for ptr in envCStrings { free(ptr) } }

    var pid: pid_t = 0
    let spawnResult = (argvCStrings + [nil]).withUnsafeBufferPointer { argvBuf in
      (envCStrings + [nil]).withUnsafeBufferPointer { envBuf in
        executable.path.withCString { execPath in
          posix_spawn(&pid, execPath, &actions, &attrs, argvBuf.baseAddress, envBuf.baseAddress)
        }
      }
    }
    // Always release the child end in the parent — the child has its own dup'd copies.
    close(childFD)
    guard spawnResult == 0 else {
      close(controllerFD)
      throw PTYError.spawn(errno: spawnResult)
    }

    // FD_CLOEXEC so a future spawn doesn't leak the controller end into another child.
    let fdFlags = fcntl(controllerFD, F_GETFD)
    if fdFlags >= 0 {
      _ = fcntl(controllerFD, F_SETFD, fdFlags | FD_CLOEXEC)
    }

    let ptyHandle = FileHandle(fileDescriptor: controllerFD, closeOnDealloc: true)

    let (onExit, exitCont) = AsyncStream<Int32>.makeStream(bufferingPolicy: .unbounded)

    // Per-child kqueue NOTE_EXIT watcher. Avoids installing a global SIGCHLD
    // handler that would conflict with Foundation.Process or other libdispatch
    // users in the same process.
    let queue = DispatchQueue(label: "smoovmux.pty.exit.\(pid)")
    let source = DispatchSource.makeProcessSource(
      identifier: pid, eventMask: .exit, queue: queue)
    source.setEventHandler {
      var status: Int32 = 0
      _ = waitpid(pid, &status, 0)
      exitCont.yield(decodeExitStatus(status))
      exitCont.finish()
      source.cancel()
    }
    source.resume()

    return PTYChild(pid: pid, pty: ptyHandle, onExit: onExit)
  }

  /// Update the controlling terminal's window size via `TIOCSWINSZ`. The child
  /// receives `SIGWINCH` if it has installed a handler.
  public static func resize(_ child: PTYChild, cols: UInt16, rows: UInt16) throws {
    var ws = winsize()
    ws.ws_row = rows
    ws.ws_col = cols
    ws.ws_xpixel = 0
    ws.ws_ypixel = 0
    let result = withUnsafeMutablePointer(to: &ws) { ptr -> Int32 in
      ioctl(child.pty.fileDescriptor, UInt(truncatingIfNeeded: TIOCSWINSZ), ptr)
    }
    if result != 0 { throw PTYError.ioctl(errno: errno) }
  }
}

/// Translate a `waitpid` status word into a single `Int32`. Normal exits yield
/// the exit code (0–255); signal kills yield `128 + signo` (the shell convention).
private func decodeExitStatus(_ status: Int32) -> Int32 {
  if (status & 0x7f) == 0 {
    return (status >> 8) & 0xff
  }
  return 128 + (status & 0x7f)
}
