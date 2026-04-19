import Foundation

/// Kind of tmux-backed session. Every pane in smoovmux is a tmux pane; the
/// kind captures *where* the tmux server is running.
public enum SessionKind: Sendable, Equatable {
  case localShell
  case ssh(host: String)
}

/// A live session. Implementations live outside this module (e.g. in the app
/// target or a future `LocalSession` / `SSHSession` package).
public protocol Session: AnyObject, Sendable {
  var id: UUID { get }
  var kind: SessionKind { get }
  var isRunning: Bool { get }

  func start() async throws
  func stop() async
}
