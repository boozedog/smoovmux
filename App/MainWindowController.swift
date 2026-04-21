import AppKit

/// Single-window host. Custom tab bar lives here in M2+; for now it hosts
/// one `SmoovSurfaceView` as its content view.
///
/// Do NOT use `addTabbedWindow` / `NSWindow.TabbingMode` — AeroSpace/yabai see
/// native tabs as separate windows. Custom tab bar in one NSWindow. (#2, CLAUDE.md)
final class MainWindowController: NSWindowController, NSWindowDelegate {
  private let surfaceView: SmoovSurfaceView

  init(ghosttyApp: GhosttyApp) {
    // M1 / issue #25: no command → libghostty spawns the user's login
    // shell from config defaults. #26 replaces this with smoovmux-relay +
    // SMOOVMUX_PANE_SOCKET, running tmux end-to-end.
    self.surfaceView = SmoovSurfaceView(
      app: ghosttyApp,
      config: SmoovSurfaceView.Config()
    )

    let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
      styleMask: styleMask,
      backing: .buffered,
      defer: false
    )
    window.title = "smoovmux"
    window.tabbingMode = .disallowed
    window.center()
    window.contentView = surfaceView

    super.init(window: window)
    window.delegate = self
    window.makeFirstResponder(surfaceView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }
}
