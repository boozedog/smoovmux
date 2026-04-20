import Darwin
import Foundation

/// `smoovmux-relay` — the libghostty-side half of the pane wire.
///
/// libghostty's termio backend only knows how to spawn a child PTY (see
/// `src/termio/backend.zig` in our ghostty submodule); it has no API for
/// injecting bytes from the parent. We work around that by setting each
/// surface's `command` to this binary, which connects to the per-pane unix
/// socket given via `SMOOVMUX_PANE_SOCKET` and pumps:
///
///   stdin  -> socket   (libghostty keystrokes -> tmux send-keys)
///   socket -> stdout   (tmux %output           -> libghostty render)
///
/// No protocol framing — a single SOCK_STREAM preserves byte order in each
/// direction. Either end's EOF tears down the relay.

@inline(__always)
private func die(_ message: String, code: Int32 = 2) -> Never {
  FileHandle.standardError.write(Data("smoovmux-relay: \(message)\n".utf8))
  exit(code)
}

private func openSocket(path: String) -> Int32 {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  if fd < 0 { die("socket() failed: errno=\(errno)") }

  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  let pathBytes = Array(path.utf8)
  let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
  if pathBytes.count >= maxLen {
    die("socket path too long (max \(maxLen - 1) bytes)")
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
  let result = withUnsafePointer(to: &addr) { addrPtr in
    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
      Darwin.connect(fd, sockPtr, addrLen)
    }
  }
  if result != 0 { die("connect(\(path)) failed: errno=\(errno)") }
  return fd
}

private func pump(from src: Int32, to dst: Int32) {
  var buffer = [UInt8](repeating: 0, count: 4096)
  while true {
    let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
      Darwin.read(src, ptr.baseAddress, ptr.count)
    }
    if bytesRead == 0 { return }
    if bytesRead < 0 {
      if errno == EINTR { continue }
      return
    }
    var offset = 0
    while offset < bytesRead {
      let written = buffer.withUnsafeBufferPointer { ptr -> Int in
        guard let base = ptr.baseAddress else { return 0 }
        return Darwin.write(dst, base.advanced(by: offset), bytesRead - offset)
      }
      if written <= 0 {
        if errno == EINTR { continue }
        return
      }
      offset += written
    }
  }
}

guard let socketPath = ProcessInfo.processInfo.environment["SMOOVMUX_PANE_SOCKET"] else {
  die("SMOOVMUX_PANE_SOCKET is not set")
}

let sockFD = openSocket(path: socketPath)

// Pump stdin -> socket on a background thread so we can run socket -> stdout
// inline. When stdin EOFs, half-close the socket so the peer learns we're
// done writing; when the socket EOFs (or the peer closes both halves), the
// inline pump returns and the process exits, which in turn drops the stdin
// pump thread.
let stdinPumpThread = Thread {
  pump(from: 0, to: sockFD)
  shutdown(sockFD, SHUT_WR)
}
stdinPumpThread.name = "smoovmux-relay.stdin"
stdinPumpThread.start()

pump(from: sockFD, to: 1)
exit(0)
