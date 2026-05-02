import AppKit
import SwiftUI

/// Single-window host for custom workspace tabs.
///
/// Do NOT use `addTabbedWindow` / native `NSWindow` tabs — AeroSpace/yabai see
/// native tabs as separate windows. Custom tab chrome stays inside one NSWindow.
/// (#2, CLAUDE.md)
final class MainWindowController: NSWindowController, NSWindowDelegate {
  let tabManager: WorkspaceTabManager

  init(tabManager: WorkspaceTabManager) {
    self.tabManager = tabManager

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
    window.contentView = NSHostingView(rootView: TabbedRootView(tabManager: tabManager))

    super.init(window: window)
    window.delegate = self
  }

  @objc func newTab(_ sender: Any?) {
    tabManager.addTab()
  }

  @objc func closeTab(_ sender: Any?) {
    tabManager.closeSelectedTab()
  }

  @objc func splitRight(_ sender: Any?) {
    tabManager.selectedPane?.splitRight()
  }

  @objc func splitDown(_ sender: Any?) {
    tabManager.selectedPane?.splitDown()
  }

  @objc func closePane(_ sender: Any?) {
    tabManager.selectedPane?.closePane()
  }

  @objc func selectNextTab(_ sender: Any?) {
    tabManager.selectNextTab()
  }

  @objc func selectPreviousTab(_ sender: Any?) {
    tabManager.selectPreviousTab()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }
}
