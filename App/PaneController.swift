import AppKit
import Foundation
import PaneRelay
import SessionCore
import SmoovLog
import TmuxCC

/// Orchestrates one tmux pane end-to-end.
///
/// The wiring fans out from here:
///
///     libghostty surface  ──(stdin)──▶  smoovmux-relay  ──(AF_UNIX)──▶  PaneConnection
///                          ◀─(stdout)──                ◀──────────────
///                                                                     │
///                                                                     ▼
///                                                             TmuxGateway.send(...)
///                                                             TmuxGateway.subscribe(paneId:)
///                                                                     │
///                                                                     ▼
///                                                             LocalTmuxSession PTY
///
/// Smoovmux doesn't own the PTY libghostty runs — libghostty's termio backend
/// spawns whatever `command` we hand it and reads/writes that child's tty
/// itself. The `smoovmux-relay` binary is the child: it just pumps bytes
/// between its stdio and a unix socket. The socket's server side is us, and
/// we route into/out of `TmuxGateway` from there. See `Sources/PaneRelay`
/// for the transport, `Sources/smoovmux-relay` for the helper binary, and
/// issue #26 for the end-to-end design.
@MainActor
final class PaneController {
  enum StartError: Error {
    case relayBinaryMissing
    case socketDirCreationFailed(Error)
    case relayListenFailed(RelayServer.ListenError)
    case tmuxLaunchFailed(LocalTmuxSession.LaunchError)
  }

  /// The view the window controller hosts. Owned by this controller; its
  /// lifetime is tied to the pane.
  let surfaceView: SmoovSurfaceView

  // M1 single-pane: tmux's first pane is `%0`. Discovery of pane ids via
  // `list-panes` lands in M2+ when we have splits.
  private let paneId: UInt = 0
  private let paneTarget = "%0"

  private let relay: RelayServer
  private let launch: LocalTmuxSession.Launch
  private let socketDir: URL

  private var backgroundTasks: [Task<Void, Never>] = []
  private var lastReportedSize: (cols: UInt16, rows: UInt16) = (0, 0)

  init(ghosttyApp: GhosttyApp) throws {
    let bundle = Bundle.main
    guard
      let relayPath = bundle.path(
        forResource: "smoovmux-relay", ofType: nil, inDirectory: "bin")
    else {
      throw StartError.relayBinaryMissing
    }
    let bundledTmux = bundle.path(
      forResource: "tmux", ofType: nil, inDirectory: "bin")

    // Per-pane socket in a per-app scratch dir. Kept short: sockaddr_un's
    // sun_path is 104 bytes on macOS, and deep `$TMPDIR` paths blow it.
    // `/tmp/smoovmux-<pid>/pane-<short>.sock` stays well under that.
    let scratchName = "smoovmux-\(getpid())"
    let socketDir = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent(scratchName, isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: socketDir, withIntermediateDirectories: true)
    } catch {
      throw StartError.socketDirCreationFailed(error)
    }
    self.socketDir = socketDir

    let shortId = UUID().uuidString.prefix(8).lowercased()
    let socketPath = socketDir.appendingPathComponent("pane-\(shortId).sock").path

    let relay: RelayServer
    do {
      relay = try RelayServer.listen(socketPath: socketPath)
    } catch let error as RelayServer.ListenError {
      throw StartError.relayListenFailed(error)
    }
    self.relay = relay

    let launch: LocalTmuxSession.Launch
    do {
      launch = try LocalTmuxSession.start(bundledTmuxFallback: bundledTmux)
    } catch let error as LocalTmuxSession.LaunchError {
      // Relay is already listening; drop it so the socket file is reaped.
      Task { await relay.stop() }
      throw StartError.tmuxLaunchFailed(error)
    }
    self.launch = launch

    var config = SmoovSurfaceView.Config()
    config.command = relayPath
    config.env = ["SMOOVMUX_PANE_SOCKET": socketPath]
    self.surfaceView = SmoovSurfaceView(app: ghosttyApp, config: config)

    SmoovLog.info(
      "pane %\(paneId) socket=\(socketPath) tmux=\(launch.socketLabel) pid=\(launch.pid)"
    )

    wire()
  }

  deinit {
    for task in backgroundTasks { task.cancel() }
    let dir = socketDir
    let relay = self.relay
    Task.detached {
      await relay.stop()
      try? FileManager.default.removeItem(at: dir)
    }
  }

  // MARK: - Wiring

  private func wire() {
    let gateway = launch.gateway
    let relay = self.relay
    let paneId = self.paneId
    let paneTarget = self.paneTarget

    surfaceView.onResize = { [weak self] cols, rows in
      self?.handleResize(cols: cols, rows: rows)
    }

    backgroundTasks.append(
      Task { [weak self] in
        // Pre-subscribe on the actor BEFORE the drain starts so no %output
        // token lands without a sink and gets dropped.
        let outputStream = await gateway.subscribe(paneId: paneId)

        // Drain tmux tokens into the actor in its own child task. Runs
        // until the PTY input stream closes or tmux sends `%exit`.
        let drainTask = Task { await gateway.start() }

        await self?.runRelayLoop(
          outputStream: outputStream,
          gateway: gateway,
          relay: relay,
          paneTarget: paneTarget
        )

        // Relay loop exited (surface closed). Don't cancel the drain —
        // the gateway's transitionToDetached handles cleanup when the
        // PTY input stream itself ends.
        await drainTask.value
      })
  }

  /// Accept the relay child's connection, then pump bytes both ways until
  /// one side closes. `PaneConnection` is the single ownership holder of
  /// the accepted fd; tearing it down closes the socket.
  private func runRelayLoop(
    outputStream: AsyncStream<Data>,
    gateway: TmuxGateway,
    relay: RelayServer,
    paneTarget: String
  ) async {
    let connection: PaneConnection
    do {
      connection = try await relay.accept()
    } catch {
      SmoovLog.warn("relay accept failed: \(error)")
      return
    }

    // tmux %output → libghostty (via relay stdout). Detached because
    // `connection.write` does a blocking Darwin.write(2) that would
    // otherwise stall the MainActor on large bursts.
    let outputPump = Task.detached { [connection] in
      for await chunk in outputStream {
        do {
          try connection.write(chunk)
        } catch {
          SmoovLog.warn("pane output write failed: \(error)")
          return
        }
      }
    }

    // libghostty keystrokes → tmux send-keys. Detached mirrors the output
    // side and also avoids constant actor hops from the MainActor.
    let inputPump = Task.detached { [connection] in
      for await chunk in connection.fromRelay {
        await Self.sendBytes(chunk, to: paneTarget, gateway: gateway)
      }
    }

    // Await the close handshake: either the surface exited (relay closes
    // its write side) or the gateway detached (output stream ends). We
    // tear down the remaining half and return.
    for await _ in connection.onClose { break }
    outputPump.cancel()
    inputPump.cancel()
    connection.close()
  }

  /// Forward bytes to tmux via `send-keys -t <target> -H <hex ...>`.
  ///
  /// Chunked to keep single commands short; tmux's command parser has
  /// historically had trouble with very long lines (see iTerm2's 1000-byte
  /// literal / 125-byte hex cap). 192 bytes of input per command yields a
  /// ~600-character command which is well inside safe limits.
  ///
  /// `nonisolated` so the caller (a detached input-pump Task) can run this
  /// on its own executor without hopping back to MainActor. The actual
  /// `gateway.send` call already does the right actor hop to `TmuxGateway`.
  nonisolated private static func sendBytes(
    _ data: Data, to target: String, gateway: TmuxGateway
  ) async {
    guard !data.isEmpty else { return }
    let maxPerCommand = 192
    var start = data.startIndex
    while start < data.endIndex {
      // `index(offsetBy:limitedBy:)` — plain `offsetBy:` traps when the
      // advance would go past endIndex, which for our 7-byte "whoami\n"
      // against maxPerCommand=192 is immediate.
      let end =
        data.index(start, offsetBy: maxPerCommand, limitedBy: data.endIndex)
        ?? data.endIndex
      let slice = data[start..<end]
      start = end

      var command = "send-keys -t \(target) -H"
      command.reserveCapacity(command.count + slice.count * 3)
      for byte in slice {
        command.append(" ")
        command.append(String(format: "%02x", byte))
      }
      do {
        _ = try await gateway.send(command)
      } catch {
        SmoovLog.warn("send-keys failed: \(error)")
        return
      }
    }
  }

  // MARK: - Resize

  /// Call when the surface's cell grid changes. Forwards to tmux as a
  /// `refresh-client -C <cols>,<rows>`. Deduped so a flurry of identical
  /// resizes produced by layout settling doesn't flood the command queue.
  func handleResize(cols: UInt16, rows: UInt16) {
    guard cols > 0, rows > 0 else { return }
    if cols == lastReportedSize.cols, rows == lastReportedSize.rows { return }
    lastReportedSize = (cols, rows)
    let gateway = launch.gateway
    Task {
      do {
        _ = try await gateway.send("refresh-client -C \(cols),\(rows)")
      } catch {
        SmoovLog.warn("refresh-client failed: \(error)")
      }
    }
  }
}
