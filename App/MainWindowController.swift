import AppKit
import SwiftUI
import WorkspaceState

/// Single-window host for custom workspace tabs.
///
/// Do NOT use `addTabbedWindow` / native `NSWindow` tabs — AeroSpace/yabai see
/// native tabs as separate windows. Custom tab chrome stays inside one NSWindow.
/// (#2, CLAUDE.md)
final class MainWindowController: NSWindowController, NSWindowDelegate {
  let tabManager: WorkspaceTabManager
  private let stateStore: WorkspaceStateStore

  init(tabManager: WorkspaceTabManager, stateStore: WorkspaceStateStore, restoredWindowFrame: WorkspaceWindowFrame?) {
    self.tabManager = tabManager
    self.stateStore = stateStore

    let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    let window = NSWindow(
      contentRect: restoredWindowFrame?.rect ?? NSRect(x: 0, y: 0, width: 960, height: 600),
      styleMask: styleMask,
      backing: .buffered,
      defer: false
    )
    window.title = "smoovmux"
    window.tabbingMode = .disallowed
    if restoredWindowFrame == nil {
      window.center()
    }
    window.contentView = NSHostingView(rootView: TabbedRootView(tabManager: tabManager))

    super.init(window: window)
    window.delegate = self
    tabManager.onStateChange = { [weak self] in
      self?.saveState()
    }
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

  func windowDidMove(_ notification: Notification) {
    saveState()
  }

  func windowDidResize(_ notification: Notification) {
    saveState()
  }

  func windowWillClose(_ notification: Notification) {
    saveState()
  }

  private func saveState() {
    stateStore.save(tabManager.snapshot(windowFrame: window.map { WorkspaceWindowFrame($0.frame) }))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }
}
