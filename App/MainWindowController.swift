import AppKit
import PaneLauncher
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

    let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    let window = NSWindow(
      contentRect: restoredWindowFrame?.rect ?? NSRect(x: 0, y: 0, width: 960, height: 600),
      styleMask: styleMask,
      backing: .buffered,
      defer: false
    )
    window.title = Self.title(for: tabManager)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.backgroundColor = .black
    window.tabbingMode = .disallowed
    if restoredWindowFrame == nil {
      window.center()
    }
    window.contentView = NSHostingView(rootView: TabbedRootView(tabManager: tabManager))

    super.init(window: window)
    window.delegate = self
    tabManager.onStateChange = { [weak self] in
      self?.updateWindowTitle()
      self?.saveState()
    }
    updateWindowTitle()
  }

  @objc func newTab(_ sender: Any?) {
    tabManager.showLauncher(action: .newTab)
  }

  @objc func closeTab(_ sender: Any?) {
    tabManager.closeSelectedTab()
  }

  @objc func splitRight(_ sender: Any?) {
    tabManager.showLauncher(action: .splitRight)
  }

  @objc func splitDown(_ sender: Any?) {
    tabManager.showLauncher(action: .splitDown)
  }

  @objc func closePane(_ sender: Any?) {
    tabManager.selectedPane?.closePane()
  }

  @objc func toggleRightSidebar(_ sender: Any?) {
    tabManager.toggleRightSidebar()
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

  func saveState() {
    stateStore.save(tabManager.snapshot(windowFrame: window.map { WorkspaceWindowFrame($0.frame) }))
  }

  private func updateWindowTitle() {
    window?.title = Self.title(for: tabManager)
  }

  private static func title(for tabManager: WorkspaceTabManager) -> String {
    tabManager.selectedTabTitle
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }
}
