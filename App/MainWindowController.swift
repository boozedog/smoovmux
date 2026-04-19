import AppKit

/// Single-window host. Custom tab bar lives here in M2+; for now it's just a
/// blank content view proving the build wires up.
///
/// Do NOT use `addTabbedWindow` / `NSWindow.TabbingMode` — AeroSpace/yabai see
/// native tabs as separate windows. Custom tab bar in one NSWindow. (#2, CLAUDE.md)
final class MainWindowController: NSWindowController, NSWindowDelegate {
  convenience init() {
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
    self.init(window: window)
    window.delegate = self
  }
}
