import Darwin
import Foundation
import Testing

@testable import SessionCore

/// Integration tests for the real tmux launcher. Gated on `SMOOVMUX_INTEGRATION=1`
/// so CI (which may not have a usable tmux) skips the suite by default.
@Suite(
  "LocalTmuxSession",
  .enabled(if: ProcessInfo.processInfo.environment["SMOOVMUX_INTEGRATION"] == "1")
)
struct LocalTmuxSessionTests {
  @Test func launchesTmuxAndAnswersDisplayMessage() async throws {
    let launch = try LocalTmuxSession.start(cols: 80, rows: 24)
    let drain = Task { await launch.gateway.start() }
    defer {
      kill(launch.pid, SIGTERM)
      drain.cancel()
    }

    // Wait for %session-changed to flip us out of .connecting.
    var states = launch.gateway.stateStream.makeAsyncIterator()
    #expect(await states.next() == .connecting)
    let attached = await states.next()
    guard case .attached = attached else {
      Issue.record("expected .attached, got \(String(describing: attached))")
      return
    }

    let lines = try await launch.gateway.send("display-message -p 'hello'")
    #expect(lines == ["hello"])

    // Socket file lives at /tmp/tmux-<uid>/<label> by default.
    let socketPath = "/tmp/tmux-\(getuid())/\(launch.socketLabel)"
    #expect(FileManager.default.fileExists(atPath: socketPath))

    _ = try? await launch.gateway.send("kill-server")

    // kill-server should cause the PTY to close and the child to exit.
    var exits = launch.childExit.makeAsyncIterator()
    _ = await exits.next()
    await drain.value
  }

  @Test func socketLabelEmbedsWindowUUID() throws {
    let windowId = UUID()
    let launch = try LocalTmuxSession.start(cols: 80, rows: 24, windowId: windowId)
    defer { kill(launch.pid, SIGTERM) }
    #expect(launch.socketLabel == "smoovmux-\(windowId.uuidString.lowercased())")
    #expect(launch.windowId == windowId)
  }
}
