import AppKit

/// Single-window host. Custom tab bar lives here in M2+; for now it hosts
/// the one `SmoovSurfaceView` owned by a `PaneController` as its content view.
///
/// Do NOT use `addTabbedWindow` / `NSWindow.TabbingMode` — AeroSpace/yabai see
/// native tabs as separate windows. Custom tab bar in one NSWindow. (#2, CLAUDE.md)
final class MainWindowController: NSWindowController, NSWindowDelegate {
  private let pane: PaneController

  init(pane: PaneController) {
    self.pane = pane

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
    window.contentView = pane.surfaceView

    super.init(window: window)
    window.delegate = self
    window.makeFirstResponder(pane.surfaceView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }
}
