import AppKit
import SessionCore
import SmoovAppCommands
import SmoovLog
import WorkspaceState

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
  private(set) var ghosttyApp: GhosttyApp?
  private var windowControllersById: [UUID: MainWindowController] = [:]
  private var settingsWindowController: SettingsWindowController?
  private var stateStore: WorkspaceStateStore?
  private var windowMenu: NSMenu?
  private var screensMenu: NSMenu?

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
    fileMenu.addItem(NSMenuItem.separator())
    addMenuItem(AppCommand.splitRight, to: fileMenu, action: #selector(Self.splitRight(_:)))
    addMenuItem(AppCommand.splitDown, to: fileMenu, action: #selector(Self.splitDown(_:)))
    addMenuItem(AppCommand.closePane, to: fileMenu, action: #selector(Self.closePane(_:)))

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

    let screensMenuItem = NSMenuItem()
    mainMenu.addItem(screensMenuItem)
    let screensMenu = NSMenu(title: "Screens")
    screensMenu.delegate = self
    screensMenuItem.submenu = screensMenu
    self.screensMenu = screensMenu
    rebuildScreensMenu()

    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = NSMenu(title: "Window")
    windowMenu.delegate = self
    windowMenuItem.submenu = windowMenu
    self.windowMenu = windowMenu
    rebuildWindowMenu()

    NSApp.mainMenu = mainMenu
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === windowMenu {
      rebuildWindowMenu()
    } else if menu === screensMenu {
      rebuildScreensMenu()
    }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    true
  }

  private func rebuildWindowMenu() {
    guard let windowMenu else { return }

    windowMenu.removeAllItems()
    for item in WindowMenuPolicy.items(for: orderedWindowMenuWindows()) {
      addWindowMenuItem(item, to: windowMenu)
    }
  }

  private func rebuildScreensMenu() {
    guard let screensMenu else { return }

    screensMenu.removeAllItems()
    for item in ScreensMenuPolicy.items(for: currentScreensMenuScreens()) {
      addScreensMenuItem(item, to: screensMenu)
    }
  }

  private func currentScreensMenuScreens() -> [ScreensMenuScreen] {
    guard let controller = keyMainWindowController else { return [] }
    let selectedTabId = controller.tabManager.selectedTabId
    return controller.tabManager.tabs.enumerated().map { offset, tab in
      ScreensMenuScreen(
        id: tab.id,
        title: tab.title,
        isSelected: tab.id == selectedTabId,
        index: offset + 1
      )
    }
  }

  private func orderedWindowMenuWindows() -> [WindowMenuWindow] {
    var seenIds = Set<UUID>()
    let orderedIds = NSApp.orderedWindows.compactMap { window -> UUID? in
      guard let controller = window.windowController as? MainWindowController,
        windowControllersById[controller.id] === controller,
        !seenIds.contains(controller.id)
      else { return nil }

      seenIds.insert(controller.id)
      return controller.id
    }

    let remainingIds = windowControllersById.keys
      .filter { !seenIds.contains($0) }
      .sorted { $0.uuidString < $1.uuidString }

    return (orderedIds + remainingIds).compactMap { id in
      guard let controller = windowControllersById[id], let window = controller.window else { return nil }
      return WindowMenuWindow(id: id, title: window.title, isKey: window.isKeyWindow)
    }
  }

  private func addWindowMenuItem(_ item: WindowMenuItem, to menu: NSMenu) {
    switch item {
    case .command(let command):
      let menuItem = menu.addItem(
        withTitle: command.title,
        action: action(for: command),
        keyEquivalent: command.shortcut?.key ?? ""
      )
      menuItem.target = target(for: command)
      if let shortcut = command.shortcut {
        menuItem.keyEquivalentModifierMask = shortcut.modifiers.eventModifierFlags
      }
    case .separator:
      menu.addItem(NSMenuItem.separator())
    case .window(let window):
      let menuItem = menu.addItem(
        withTitle: window.title,
        action: #selector(Self.focusWindowFromMenu(_:)),
        keyEquivalent: ""
      )
      menuItem.target = self
      menuItem.representedObject = window.id.uuidString
      menuItem.state = window.isChecked ? .on : .off
    }
  }

  private func addScreensMenuItem(_ item: ScreensMenuItem, to menu: NSMenu) {
    switch item {
    case .command(let command):
      let menuItem = menu.addItem(
        withTitle: command.title,
        action: action(for: command),
        keyEquivalent: command.shortcut?.key ?? ""
      )
      menuItem.target = self
      if let shortcut = command.shortcut {
        menuItem.keyEquivalentModifierMask = shortcut.modifiers.eventModifierFlags
      }
    case .separator:
      menu.addItem(NSMenuItem.separator())
    case .screen(let screen):
      let menuItem = menu.addItem(
        withTitle: screen.title,
        action: #selector(Self.selectScreenFromMenu(_:)),
        keyEquivalent: screen.shortcut?.key ?? ""
      )
      menuItem.target = self
      menuItem.representedObject = screen.id.uuidString
      menuItem.state = screen.isChecked ? .on : .off
      if let shortcut = screen.shortcut {
        menuItem.keyEquivalentModifierMask = shortcut.modifiers.eventModifierFlags
      }
    }
  }

  private func action(for command: WindowMenuCommand) -> Selector {
    switch command {
    case .minimize:
      return #selector(NSWindow.performMiniaturize(_:))
    case .zoom:
      return #selector(NSWindow.performZoom(_:))
    case .zoomPane:
      return #selector(Self.zoomSelectedPane(_:))
    case .bringAllToFront:
      return #selector(NSApplication.arrangeInFront(_:))
    }
  }

  private func target(for command: WindowMenuCommand) -> AnyObject? {
    switch command {
    case .minimize, .zoom:
      return nil
    case .zoomPane:
      return self
    case .bringAllToFront:
      return NSApp
    }
  }

  private func action(for command: AppCommand) -> Selector {
    switch command {
    case .newTab:
      return #selector(Self.newTab(_:))
    case .closeTab:
      return #selector(Self.closeTab(_:))
    case .nextTab:
      return #selector(Self.selectNextTab(_:))
    case .previousTab:
      return #selector(Self.selectPreviousTab(_:))
    case .newWindow, .splitRight, .splitDown, .closePane, .toggleRightSidebar:
      return #selector(Self.noopMenuAction(_:))
    }
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

  @objc private func selectScreenFromMenu(_ sender: Any?) {
    guard let menuItem = sender as? NSMenuItem,
      let rawId = menuItem.representedObject as? String,
      let id = UUID(uuidString: rawId)
    else { return }

    keyMainWindowController?.selectScreen(id: id)
  }

  @objc private func noopMenuAction(_ sender: Any?) {}

  @objc private func zoomSelectedPane(_ sender: Any?) {
    keyMainWindowController?.toggleSelectedPaneZoom(sender)
  }

  @objc private func focusWindowFromMenu(_ sender: Any?) {
    guard let menuItem = sender as? NSMenuItem,
      let rawId = menuItem.representedObject as? String,
      let id = UUID(uuidString: rawId),
      let controller = windowControllersById[id]
    else { return }

    controller.window?.makeKeyAndOrderFront(sender)
    NSApp.activate(ignoringOtherApps: true)
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
