import Darwin
import Foundation
import Testing

@testable import PaneRelay

@Suite("PaneRelay.RelayServer")
struct RelayServerTests {
  @Test func acceptForwardsClientWritesToFromRelay() async throws {
    let path = uniqueSocketPath()
    let server = try RelayServer.listen(socketPath: path)

    let acceptTask = Task { try await server.accept() }
    let clientFD = try connectClient(path: path)
    setNonblocking(clientFD)

    let conn = try await acceptTask.value

    let payload = Data("hello from client\n".utf8)
    let written = writeAll(clientFD, payload)
    #expect(written == payload.count)

    let received = await readUntilCount(stream: conn.fromRelay, atLeast: payload.count, timeout: 2.0)
    #expect(received == payload)

    Darwin.close(clientFD)
    conn.close()
    await server.stop()
  }

  @Test func writeReachesClient() async throws {
    let path = uniqueSocketPath()
    let server = try RelayServer.listen(socketPath: path)

    let acceptTask = Task { try await server.accept() }
    let clientFD = try connectClient(path: path)
    setNonblocking(clientFD)

    let conn = try await acceptTask.value

    let payload = Data("response from server\n".utf8)
    try conn.write(payload)

    let received = readFD(clientFD, atLeast: payload.count, timeout: 2.0)
    #expect(received == payload)

    Darwin.close(clientFD)
    conn.close()
    await server.stop()
  }

  @Test func clientHangupFinishesFromRelayAndFiresOnClose() async throws {
    let path = uniqueSocketPath()
    let server = try RelayServer.listen(socketPath: path)

    let acceptTask = Task { try await server.accept() }
    let clientFD = try connectClient(path: path)
    let conn = try await acceptTask.value

    Darwin.close(clientFD)

    var inIter = conn.fromRelay.makeAsyncIterator()
    var closeIter = conn.onClose.makeAsyncIterator()

    // fromRelay drains and finishes; iter eventually returns nil.
    let drained = await drainUntilNil(iterator: &inIter, timeout: 2.0)
    #expect(drained)

    let closeEvent: Void? = await waitForFirst(iterator: &closeIter, timeout: 1.0)
    #expect(closeEvent != nil)

    await server.stop()
  }

  @Test func acceptBuffersConnectionThatArrivesFirst() async throws {
    let path = uniqueSocketPath()
    let server = try RelayServer.listen(socketPath: path)

    // Connect before anyone calls accept; the server must buffer the fd.
    let clientFD = try connectClient(path: path)
    setNonblocking(clientFD)

    // Give the dispatch source a chance to fire and the Task to settle.
    try await Task.sleep(nanoseconds: 100_000_000)

    let conn = try await server.accept()

    let payload = Data("buffered\n".utf8)
    _ = writeAll(clientFD, payload)
    let received = await readUntilCount(stream: conn.fromRelay, atLeast: payload.count, timeout: 2.0)
    #expect(received == payload)

    Darwin.close(clientFD)
    conn.close()
    await server.stop()
  }

  @Test func stopFailsPendingAccept() async throws {
    let path = uniqueSocketPath()
    let server = try RelayServer.listen(socketPath: path)

    let acceptTask = Task { try await server.accept() }

    // Yield so the waiter is installed.
    try await Task.sleep(nanoseconds: 50_000_000)
    await server.stop()

    do {
      _ = try await acceptTask.value
      Issue.record("expected accept to throw after stop")
    } catch RelayServer.AcceptError.stopped {
      // ok
    }
  }

  @Test func writeAfterCloseThrows() async throws {
    let path = uniqueSocketPath()
    let server = try RelayServer.listen(socketPath: path)

    let acceptTask = Task { try await server.accept() }
    let clientFD = try connectClient(path: path)
    let conn = try await acceptTask.value
    Darwin.close(clientFD)
    conn.close()

    do {
      try conn.write(Data("nope".utf8))
      Issue.record("write should have thrown after close")
    } catch PaneConnection.WriteError.closed {
      // ok
    } catch PaneConnection.WriteError.io {
      // also acceptable: the underlying fd is gone
    }
    await server.stop()
  }
}

// MARK: - Helpers (file-private; Swift Testing doesn't reuse XCTest's class scaffolding)

private func uniqueSocketPath() -> String {
  // Keep paths short — sun_path is 104 bytes on Darwin and `NSTemporaryDirectory()`
  // can already eat 60 of those.
  let suffix = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12)
  return "/tmp/smux-\(suffix).sock"
}

private func connectClient(path: String) throws -> Int32 {
  let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
  if fd < 0 { throw POSIXError(.EBADF) }
  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  let pathBytes = Array(path.utf8)
  let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
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
  if result != 0 {
    Darwin.close(fd)
    throw POSIXError(.ECONNREFUSED)
  }
  return fd
}

private func setNonblocking(_ fd: Int32) {
  let flags = fcntl(fd, F_GETFL)
  if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
}

private func writeAll(_ fd: Int32, _ data: Data) -> Int {
  data.withUnsafeBytes { raw -> Int in
    guard let base = raw.baseAddress else { return 0 }
    var offset = 0
    while offset < raw.count {
      let written = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
      if written <= 0 {
        if errno == EINTR { continue }
        return offset
      }
      offset += written
    }
    return offset
  }
}

private func readFD(_ fd: Int32, atLeast count: Int, timeout: TimeInterval) -> Data {
  let deadline = Date().addingTimeInterval(timeout)
  var collected = Data()
  var buffer = [UInt8](repeating: 0, count: 4096)
  while collected.count < count, Date() < deadline {
    let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
      Darwin.read(fd, ptr.baseAddress, ptr.count)
    }
    if bytesRead > 0 {
      collected.append(buffer, count: bytesRead)
    } else if bytesRead == 0 {
      break
    } else {
      usleep(10_000)
    }
  }
  return collected
}

private func readUntilCount(stream: AsyncStream<Data>, atLeast count: Int, timeout: TimeInterval) async -> Data {
  await withTaskGroup(of: Data?.self) { group in
    group.addTask {
      var collected = Data()
      for await chunk in stream {
        collected.append(chunk)
        if collected.count >= count { return collected }
      }
      return collected
    }
    group.addTask {
      try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
      return nil
    }
    guard let outer = await group.next() else {
      group.cancelAll()
      return Data()
    }
    group.cancelAll()
    return outer ?? Data()
  }
}

private func drainUntilNil<I: AsyncIteratorProtocol>(
  iterator: inout I, timeout: TimeInterval
) async -> Bool where I.Element == Data {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    do {
      if try await iterator.next() == nil { return true }
    } catch {
      return true
    }
  }
  return false
}

private func waitForFirst<I: AsyncIteratorProtocol>(
  iterator: inout I, timeout: TimeInterval
) async -> I.Element? {
  // Race the iterator with a sleep. We can't pass the iterator across tasks,
  // so poll: just call next() — it will return as soon as there is an event
  // or stream finish. We rely on the source firing within the timeout.
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    do {
      if let value = try await iterator.next() { return value }
      return nil
    } catch {
      return nil
    }
  }
  return nil
}
