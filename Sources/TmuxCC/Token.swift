import Foundation

/// A parsed tmux control mode notification.
///
/// Tokens are emitted by `Parser` as it consumes bytes from a tmux `-CC` session.
/// Names and semantics mirror the `Notification` union in
/// `ghostty/src/terminal/tmux/control.zig`, which is the authoritative reference
/// for this module. See https://github.com/tmux/tmux/wiki/Control-Mode.
public enum Token: Equatable, Sendable {
  /// Payload of a `%begin`/`%end` command response block.
  case blockEnd(data: Data)

  /// Payload of a `%begin`/`%error` command response block.
  case blockError(data: Data)

  /// Raw output from a pane. `data` has already been unescaped from tmux's
  /// `\ooo` octal encoding; bytes are not guaranteed to be valid UTF-8.
  case output(paneId: UInt, data: Data)

  /// Client is now attached to session `id` named `name`.
  case sessionChanged(id: UInt, name: String)

  /// Current session was renamed to `name`.
  case sessionRenamed(name: String)

  /// A session was created or destroyed.
  case sessionsChanged

  /// tmux is exiting control mode.
  case exit

  /// A notification we don't decode in this milestone. The payload is the raw
  /// line (minus the trailing `\r?\n`) so later milestones can add handlers
  /// without changing this enum.
  case unknown(line: String)
}
