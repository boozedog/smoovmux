import Darwin
import Foundation
import SmoovLog

/// Per-pane unix-socket server. The smoovmux main app spawns one
/// `smoovmux-relay` child per libghostty surface; that child opens a
/// `SOCK_STREAM` `AF_UNIX` connection to the path given via
/// `SMOOVMUX_PANE_SOCKET`. The server hands every accepted connection back as
/// a `PaneConnection` whose `fromRelay` is keystrokes (libghostty -> tmux) and
/// `write(_:)` is `%output` bytes (tmux -> libghostty).
///
/// Why a per-pane socket instead of a shared one with a handshake: the
/// listening path *is* the identifier — the main app already knows which pane
/// it created the path for, so the first byte across the wire is real pane
/// data, not a "hello, I am pane N" frame. One fewer thing to parse, one
/// fewer protocol bug to write.
public actor RelayServer {
  public enum ListenError: Error, Equatable {
    case socket(errno: Int32)
    case bind(errno: Int32)
    case listen(errno: Int32)
    case pathTooLong
  }

  public enum AcceptError: Error, Equatable {
    case stopped
  }

  nonisolated public let socketPath: String
  private let listenFD: Int32
  private let acceptSource: DispatchSourceRead

  private var pendingFDs: [Int32] = []
  private var waiters: [CheckedContinuation<Int32, Error>] = []
  private var stopped = false

  /// Bind a `SOCK_STREAM` AF_UNIX socket at `socketPath` and start accepting.
  /// Any pre-existing file at that path is unlinked first; callers are
  /// responsible for choosing a path inside an app-private directory.
  public static func listen(socketPath: String) throws -> RelayServer {
    let listenFD = try makeListenSocket(at: socketPath)
    return RelayServer(socketPath: socketPath, listenFD: listenFD)
  }

  private init(socketPath: String, listenFD: Int32) {
    self.socketPath = socketPath
    self.listenFD = listenFD

    let queue = DispatchQueue(label: "smoovmux.relay.accept.\(listenFD)")
    let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
    self.acceptSource = source

    source.setEventHandler { [weak self] in
      // Drain everything the kernel has — read sources are level-triggered but
      // we may get more than one connection per wakeup.
      while true {
        let clientFD = Darwin.accept(listenFD, nil, nil)
        if clientFD < 0 {
          let code = errno
          switch code {
          case EAGAIN, EWOULDBLOCK, EINTR:
            return  // no more pending; wait for next wakeup
          case EBADF, ECONNABORTED, EINVAL:
            return  // listen fd torn down; cancel handler is on its way
          default:
            SmoovLog.warn("relay accept failed: errno=\(code)")
            return
          }
        }
        // FD_CLOEXEC so a future spawn doesn't leak this connection.
        let flags = fcntl(clientFD, F_GETFD)
        if flags >= 0 { _ = fcntl(clientFD, F_SETFD, flags | FD_CLOEXEC) }
        guard let self else {
          Darwin.close(clientFD)
          return
        }
        Task { await self.handleAccepted(clientFD: clientFD) }
      }
    }
    source.resume()
  }

  deinit {
    acceptSource.cancel()
    Darwin.close(listenFD)
    unlink(socketPath)
  }

  /// Wait for the next pane connection. If the relay has already connected
  /// before `accept()` is called, returns immediately with the buffered fd.
  public func accept() async throws -> PaneConnection {
    if stopped { throw AcceptError.stopped }
    if !pendingFDs.isEmpty {
      let fd = pendingFDs.removeFirst()
      return PaneConnection(fd: fd)
    }
    let fd = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
      waiters.append(cont)
    }
    return PaneConnection(fd: fd)
  }

  /// Stop accepting new connections, fail any pending `accept()` calls, and
  /// drop unclaimed accepted FDs. Already-handed-out `PaneConnection`s are
  /// untouched — the caller closes those.
  public func stop() {
    if stopped { return }
    stopped = true
    acceptSource.cancel()
    Darwin.close(listenFD)
    unlink(socketPath)
    let drainedFDs = pendingFDs
    pendingFDs.removeAll()
    for fd in drainedFDs { Darwin.close(fd) }
    let drainedWaiters = waiters
    waiters.removeAll()
    for cont in drainedWaiters { cont.resume(throwing: AcceptError.stopped) }
  }

  private func handleAccepted(clientFD: Int32) {
    if stopped {
      Darwin.close(clientFD)
      return
    }
    if !waiters.isEmpty {
      let waiter = waiters.removeFirst()
      waiter.resume(returning: clientFD)
    } else {
      pendingFDs.append(clientFD)
    }
  }

  // MARK: - Socket setup

  private static func makeListenSocket(at path: String) throws -> Int32 {
    unlink(path)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { throw ListenError.socket(errno: errno) }

    let flags = fcntl(fd, F_GETFD)
    if flags >= 0 { _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
    if pathBytes.count >= maxLen {
      Darwin.close(fd)
      throw ListenError.pathTooLong
    }
    withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
      tuplePtr.withMemoryRebound(to: CChar.self, capacity: maxLen) { cptr in
        for (index, byte) in pathBytes.enumerated() {
          cptr[index] = CChar(bitPattern: byte)
        }
        cptr[pathBytes.count] = 0
      }
    }

    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bindResult = withUnsafePointer(to: &addr) { addrPtr in
      addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        Darwin.bind(fd, sockPtr, addrLen)
      }
    }
    if bindResult != 0 {
      let code = errno
      Darwin.close(fd)
      throw ListenError.bind(errno: code)
    }

    if Darwin.listen(fd, 8) != 0 {
      let code = errno
      Darwin.close(fd)
      unlink(path)
      throw ListenError.listen(errno: code)
    }
    return fd
  }
}
