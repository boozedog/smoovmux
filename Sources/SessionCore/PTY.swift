import Darwin
import Foundation

// Darwin's Swift overlay marks `fork()` unavailable. Re-declare via its C
// symbol — we still need a real fork for the setsid + TIOCSCTTY window.
@_silgen_name("fork") private func cFork() -> pid_t

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

/// Thin Swift wrapper around `openpty(3)` + `fork(2)` + `execve(2)` for
/// spawning a child process whose controlling tty is the PTY slave. Useful for
/// app-owned local sessions and future remote/session supervisor work.
///
/// We can't use `posix_spawn` here: establishing a controlling tty requires
/// `ioctl(slave, TIOCSCTTY, 0)` *between* `setsid` and `exec`, and
/// `posix_spawn` has no hook for running custom code in that window. Without a
/// controlling tty, interactive programs can detect a degraded terminal and
/// exit or disable job-control behavior; see ghostty's `Command.zig` /
/// `pty.zig` for the same workaround.
public enum PTY {
  // macOS sys/ttycom.h: TIOCSCTTY = _IO('t', 97). Darwin's Swift overlay does
  // not export this constant.
  private static let tiocScttyRequest: UInt = 0x2000_7461

  // swiftlint:disable function_parameter_count cyclomatic_complexity

  /// Spawn `executable` under a fresh PTY pair. The child runs with `setsid`
  /// and `TIOCSCTTY` so the PTY slave becomes its controlling tty, default
  /// signal handlers, and an empty signal mask. `argv[0]` is set to
  /// `executable.path`.
  public static func spawn(
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

    // Pre-allocate everything the child needs as raw C pointers. The child
    // runs between fork and execve where Swift runtime APIs (allocation,
    // string ops, array methods) are not async-signal-safe.
    let execPathCStr = strdup(executable.path)
    let cwdCStr: UnsafeMutablePointer<CChar>? = cwd.map { strdup($0.path) }

    let argvStrings = ([executable.path] + arguments).map { strdup($0) }
    let envStrings = environment.map { strdup("\($0.key)=\($0.value)") }
    let argvBuffer = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(
      capacity: argvStrings.count + 1)
    let envBuffer = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(
      capacity: envStrings.count + 1)
    for (index, ptr) in argvStrings.enumerated() { argvBuffer[index] = ptr }
    argvBuffer[argvStrings.count] = nil
    for (index, ptr) in envStrings.enumerated() { envBuffer[index] = ptr }
    envBuffer[envStrings.count] = nil

    defer {
      free(execPathCStr)
      if let cwdCStr { free(cwdCStr) }
      for ptr in argvStrings { free(ptr) }
      for ptr in envStrings { free(ptr) }
      argvBuffer.deallocate()
      envBuffer.deallocate()
    }

    let pid = cFork()
    if pid < 0 {
      let spawnErrno = errno
      close(controllerFD)
      close(childFD)
      throw PTYError.spawn(errno: spawnErrno)
    }

    if pid == 0 {
      // Child. Only async-signal-safe libc calls from here until execve.
      close(controllerFD)
      if setsid() < 0 { _exit(127) }
      if ioctl(childFD, tiocScttyRequest, 0) < 0 { _exit(127) }
      if dup2(childFD, 0) < 0 { _exit(127) }
      if dup2(childFD, 1) < 0 { _exit(127) }
      if dup2(childFD, 2) < 0 { _exit(127) }
      if childFD > 2 { close(childFD) }
      if let cwdCStr, chdir(cwdCStr) < 0 { _exit(127) }

      // Reset signal mask and inherited dispositions to defaults. Use
      // `signal(3)` — deprecated in docs but perfectly fine for the simple
      // "restore SIG_DFL" case and safe to call here.
      var emptyMask = sigset_t()
      sigemptyset(&emptyMask)
      _ = sigprocmask(SIG_SETMASK, &emptyMask, nil)
      for signo: Int32 in 1...31 {
        _ = signal(signo, SIG_DFL)
      }

      _ = execve(execPathCStr, argvBuffer, envBuffer)
      _exit(127)
    }

    // Parent.
    close(childFD)

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

  // swiftlint:enable function_parameter_count cyclomatic_complexity

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
