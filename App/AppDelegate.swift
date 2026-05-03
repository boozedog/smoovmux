import AppKit
import SmoovAppCommands
import SmoovLog
import WorkspaceState

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private(set) var ghosttyApp: GhosttyApp?
  private var tabManager: WorkspaceTabManager?
  private var windowController: MainWindowController?
  private var stateStore: WorkspaceStateStore?

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppFonts.registerBundledFonts()
    SmoovLog.info("smoovmux launched")
    installMainMenu()

    let app: GhosttyApp
    do {
      app = try GhosttyApp()
    } catch {
      SmoovLog.error("GhosttyApp init failed: \(error)")
      NSApp.terminate(nil)
      return
    }
    self.ghosttyApp = app

    let stateStore = WorkspaceStateStore()
    self.stateStore = stateStore
    let restoredState = stateStore.load()

    let tabManager = WorkspaceTabManager(ghosttyApp: app)
    if let restoredState {
      tabManager.restore(restoredState)
    } else {
      tabManager.addTab()
    }
    self.tabManager = tabManager

    let controller = MainWindowController(
      tabManager: tabManager,
      stateStore: stateStore,
      restoredWindowFrame: restoredState?.windowFrame
    )
    controller.showWindow(nil)
    self.windowController = controller
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationWillTerminate(_ notification: Notification) {
    windowController?.saveState()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  private func installMainMenu() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenuItem.submenu = appMenu
    appMenu.addItem(
      withTitle: "Quit smoovmux",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )

    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)
    let fileMenu = NSMenu(title: "File")
    fileMenuItem.submenu = fileMenu
    addMenuItem(AppCommand.newTab, to: fileMenu, action: #selector(Self.newTab(_:)))
    addMenuItem(AppCommand.closeTab, to: fileMenu, action: #selector(Self.closeTab(_:)))
    fileMenu.addItem(NSMenuItem.separator())
    addMenuItem(AppCommand.splitRight, to: fileMenu, action: #selector(Self.splitRight(_:)))
    addMenuItem(AppCommand.splitDown, to: fileMenu, action: #selector(Self.splitDown(_:)))
    addMenuItem(AppCommand.closePane, to: fileMenu, action: #selector(Self.closePane(_:)))
    fileMenu.addItem(NSMenuItem.separator())
    addMenuItem(AppCommand.nextTab, to: fileMenu, action: #selector(Self.selectNextTab(_:)))
    addMenuItem(AppCommand.previousTab, to: fileMenu, action: #selector(Self.selectPreviousTab(_:)))

    let viewMenuItem = NSMenuItem()
    mainMenu.addItem(viewMenuItem)
    let viewMenu = NSMenu(title: "View")
    viewMenuItem.submenu = viewMenu
    addMenuItem(AppCommand.toggleRightSidebar, to: viewMenu, action: #selector(Self.toggleRightSidebar(_:)))

    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editMenu = NSMenu(title: "Edit")
    editMenuItem.submenu = editMenu
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    NSApp.mainMenu = mainMenu
  }

  @objc private func newTab(_ sender: Any?) {
    windowController?.newTab(sender)
  }

  @objc private func closeTab(_ sender: Any?) {
    windowController?.closeTab(sender)
  }

  @objc private func splitRight(_ sender: Any?) {
    windowController?.splitRight(sender)
  }

  @objc private func splitDown(_ sender: Any?) {
    windowController?.splitDown(sender)
  }

  @objc private func closePane(_ sender: Any?) {
    windowController?.closePane(sender)
  }

  @objc private func toggleRightSidebar(_ sender: Any?) {
    windowController?.toggleRightSidebar(sender)
  }

  @objc private func selectNextTab(_ sender: Any?) {
    windowController?.selectNextTab(sender)
  }

  @objc private func selectPreviousTab(_ sender: Any?) {
    windowController?.selectPreviousTab(sender)
  }

  private func addMenuItem(_ command: AppCommand, to menu: NSMenu, action: Selector) {
    let shortcut = command.shortcut
    let item = menu.addItem(
      withTitle: command.title,
      action: action,
      keyEquivalent: shortcut?.key ?? ""
    )
    item.target = self
    if let shortcut {
      item.keyEquivalentModifierMask = shortcut.modifiers.eventModifierFlags
    }
  }
}

extension KeyboardShortcutModifiers {
  fileprivate var eventModifierFlags: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if contains(.command) {
      flags.insert(.command)
    }
    if contains(.shift) {
      flags.insert(.shift)
    }
    return flags
  }
}
