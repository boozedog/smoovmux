import AppKit
import SmoovLog

final class AppDelegate: NSObject, NSApplicationDelegate {
  private(set) var ghosttyApp: GhosttyApp?
  private var pane: PaneController?
  private var windowController: MainWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
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

    let pane = PaneController(ghosttyApp: app)
    self.pane = pane

    let controller = MainWindowController(pane: pane)
    controller.showWindow(nil)
    self.windowController = controller
    NSApp.activate(ignoringOtherApps: true)
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
}
