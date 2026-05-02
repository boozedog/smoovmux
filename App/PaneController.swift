import AppKit
import SmoovLog

/// Owns one visible terminal pane.
///
/// libghostty owns the pane PTY and launches the configured child process.
/// Leaving `SmoovSurfaceView.Config.command` nil asks libghostty to start the
/// user's normal login shell. tmux is intentionally not special-cased here:
/// users who want tmux can run `tmux` inside this terminal like any other TUI.
@MainActor
final class PaneController {
  /// The view the window controller hosts. Owned by this controller; its
  /// lifetime is tied to the pane.
  let surfaceView: SmoovSurfaceView

  init(ghosttyApp: GhosttyApp) {
    let config = SmoovSurfaceView.Config()
    self.surfaceView = SmoovSurfaceView(app: ghosttyApp, config: config)
    SmoovLog.info("pane launched with default shell")
  }
}
