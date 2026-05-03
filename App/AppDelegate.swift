import AppKit
import SessionCore
import SmoovAppCommands
import SmoovLog
import WorkspaceState

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private(set) var ghosttyApp: GhosttyApp?
  private var windowControllersById: [UUID: MainWindowController] = [:]
  private var settingsWindowController: SettingsWindowController?
  private var stateStore: WorkspaceStateStore?

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppFonts.registerBundledFonts()
    SmoovLog.info("smoovmux launched")
    cleanupDroppedImages()
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
    if let restoredState, !restoredState.windows.isEmpty {
      for windowState in restoredState.windows {
        showWindow(id: windowState.id, workspaceState: windowState.workspace, activate: false)
      }
    } else {
      showLauncherWindow(activate: false)
    }

    if let selectedWindowId = restoredState?.selectedWindowId,
      let selectedWindow = windowControllersById[selectedWindowId]
    {
      selectedWindow.window?.makeKeyAndOrderFront(nil)
    } else {
      windowControllersById.values.first?.window?.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationWillTerminate(_ notification: Notification) {
    saveStateImmediately()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    if windowControllersById.isEmpty {
      showLauncherWindow(activate: true)
    }
  }

  private func cleanupDroppedImages() {
    do {
      try TerminalImageStore().cleanupFiles(olderThan: Date().addingTimeInterval(-24 * 60 * 60))
    } catch {
      SmoovLog.warn("dropped image cache cleanup failed: \(error)")
    }
  }

  private func installMainMenu() {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenuItem.submenu = appMenu
    let settingsItem = appMenu.addItem(
      withTitle: "Settings…",
      action: #selector(Self.showSettingsWindow(_:)),
      keyEquivalent: ","
    )
    settingsItem.target = self
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(
      withTitle: "Quit smoovmux",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )

    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)
    let fileMenu = NSMenu(title: "File")
    fileMenuItem.submenu = fileMenu
    addMenuItem(AppCommand.newWindow, to: fileMenu, action: #selector(Self.newWindow(_:)))
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
    let copyRawItem = editMenu.addItem(
      withTitle: "Copy Raw",
      action: #selector(SmoovSurfaceView.copyRaw(_:)),
      keyEquivalent: "c"
    )
    copyRawItem.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    NSApp.mainMenu = mainMenu
  }

  @objc func showSettingsWindow(_ sender: Any?) {
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController()
    }
    settingsWindowController?.showWindow(sender)
    settingsWindowController?.window?.makeKeyAndOrderFront(sender)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func newWindow(_ sender: Any?) {
    showLauncherWindow(activate: true)
  }

  @objc private func newTab(_ sender: Any?) {
    keyMainWindowController?.newTab(sender)
  }

  @objc private func closeTab(_ sender: Any?) {
    keyMainWindowController?.closeTab(sender)
  }

  @objc private func splitRight(_ sender: Any?) {
    keyMainWindowController?.splitRight(sender)
  }

  @objc private func splitDown(_ sender: Any?) {
    keyMainWindowController?.splitDown(sender)
  }

  @objc private func closePane(_ sender: Any?) {
    keyMainWindowController?.closePane(sender)
  }

  @objc private func toggleRightSidebar(_ sender: Any?) {
    keyMainWindowController?.toggleRightSidebar(sender)
  }

  @objc private func selectNextTab(_ sender: Any?) {
    keyMainWindowController?.selectNextTab(sender)
  }

  @objc private func selectPreviousTab(_ sender: Any?) {
    keyMainWindowController?.selectPreviousTab(sender)
  }

  private var keyMainWindowController: MainWindowController? {
    (NSApp.keyWindow?.windowController as? MainWindowController)
      ?? (NSApp.mainWindow?.windowController as? MainWindowController)
      ?? windowControllersById.values.first
  }

  @discardableResult
  private func showLauncherWindow(activate: Bool) -> MainWindowController? {
    showWindow(id: UUID(), workspaceState: .empty(), activate: activate, showLauncher: true)
  }

  @discardableResult
  private func showWindow(
    id: UUID,
    workspaceState: WorkspaceState,
    activate: Bool,
    showLauncher: Bool = false
  ) -> MainWindowController? {
    guard let ghosttyApp else { return nil }

    let tabManager = WorkspaceTabManager(ghosttyApp: ghosttyApp)
    tabManager.restore(workspaceState)
    if showLauncher || workspaceState.tabs.isEmpty {
      tabManager.showLauncher(action: .newTab)
    }

    let controller = MainWindowController(
      id: id,
      tabManager: tabManager,
      restoredWindowFrame: workspaceState.windowFrame
    )
    controller.onRequestSave = { [weak self] in
      self?.saveState()
    }
    controller.onWindowWillClose = { [weak self] id in
      self?.windowControllersById[id] = nil
      self?.saveStateImmediately()
    }
    windowControllersById[id] = controller
    controller.showWindow(nil)
    if activate {
      controller.window?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    saveState()
    return controller
  }

  private func currentState() -> AppWorkspaceState {
    let keyWindowId = keyMainWindowController?.id
    let windows = windowControllersById.values
      .sorted { $0.id.uuidString < $1.id.uuidString }
      .map { controller in
        AppWorkspaceState.Window(id: controller.id, workspace: controller.currentSnapshot())
      }
    return AppWorkspaceState(windows: windows, selectedWindowId: keyWindowId)
  }

  private func saveState() {
    stateStore?.save(currentState())
  }

  private func saveStateImmediately() {
    stateStore?.saveImmediately(currentState())
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
