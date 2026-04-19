import Darwin
import Foundation
import Testing

@testable import SessionCore

@Suite("PTY")
struct PTYTests {
  @Test func spawnCatEchoesAndForwards() async throws {
    let child = try PTY.spawn(
      executable: URL(fileURLWithPath: "/bin/cat"),
      arguments: [],
      environment: ["PATH": "/usr/bin:/bin"],
      cwd: nil,
      cols: 80,
      rows: 24
    )
    defer {
      kill(child.pid, SIGKILL)
      Task { for await _ in child.onExit {} }
    }

    setNonblocking(child.pty.fileDescriptor)
    try child.pty.write(contentsOf: Data("hello\n".utf8))

    // PTY in default cooked mode echoes input AND cat writes the line back; we
    // only require seeing "hello" at least once within the deadline.
    let collected = await readUntil(
      fd: child.pty.fileDescriptor, contains: Data("hello".utf8), timeout: 2.0)
    let text = String(data: collected, encoding: .utf8) ?? ""
    #expect(text.contains("hello"))
  }

  @Test func exitZeroIsReportedAsZero() async throws {
    let child = try PTY.spawn(
      executable: URL(fileURLWithPath: "/usr/bin/true"),
      arguments: [],
      environment: ["PATH": "/usr/bin:/bin"],
      cwd: nil,
      cols: 80,
      rows: 24
    )
    var iter = child.onExit.makeAsyncIterator()
    let code = await iter.next()
    #expect(code == 0)
    #expect(await iter.next() == nil)
  }

  @Test func nonZeroExitIsPreserved() async throws {
    let child = try PTY.spawn(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "exit 42"],
      environment: ["PATH": "/usr/bin:/bin"],
      cwd: nil,
      cols: 80,
      rows: 24
    )
    var iter = child.onExit.makeAsyncIterator()
    let code = await iter.next()
    #expect(code == 42)
  }

  @Test func resizeUpdatesWinsize() async throws {
    let child = try PTY.spawn(
      executable: URL(fileURLWithPath: "/bin/cat"),
      arguments: [],
      environment: ["PATH": "/usr/bin:/bin"],
      cwd: nil,
      cols: 80,
      rows: 24
    )
    defer {
      kill(child.pid, SIGKILL)
      Task { for await _ in child.onExit {} }
    }

    try PTY.resize(child, cols: 132, rows: 50)

    var ws = winsize()
    let result = withUnsafeMutablePointer(to: &ws) { ptr -> Int32 in
      ioctl(child.pty.fileDescriptor, UInt(truncatingIfNeeded: TIOCGWINSZ), ptr)
    }
    #expect(result == 0)
    #expect(ws.ws_col == 132)
    #expect(ws.ws_row == 50)
  }

  // MARK: - helpers

  private func setNonblocking(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFL)
    if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
  }

  private func readUntil(fd: Int32, contains needle: Data, timeout: TimeInterval) async -> Data {
    let deadline = Date().addingTimeInterval(timeout)
    var collected = Data()
    while Date() < deadline {
      var chunk = [UInt8](repeating: 0, count: 256)
      let bytesRead = chunk.withUnsafeMutableBufferPointer { ptr -> Int in
        read(fd, ptr.baseAddress, ptr.count)
      }
      if bytesRead > 0 {
        collected.append(chunk, count: bytesRead)
        let text = String(data: collected, encoding: .utf8) ?? ""
        let needleText = String(data: needle, encoding: .utf8) ?? ""
        if !needleText.isEmpty, text.contains(needleText) { return collected }
      } else if bytesRead == 0 {
        return collected
      } else {
        try? await Task.sleep(nanoseconds: 10_000_000)
      }
    }
    return collected
  }
}
