import AppKit
import SmoovLog

final class AppDelegate: NSObject, NSApplicationDelegate {
  private(set) var ghosttyApp: GhosttyApp?
  private var pane: PaneController?
  private var windowController: MainWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    SmoovLog.info("smoovmux launched")

    let app: GhosttyApp
    do {
      app = try GhosttyApp()
    } catch {
      SmoovLog.error("GhosttyApp init failed: \(error)")
      NSApp.terminate(nil)
      return
    }
    self.ghosttyApp = app

    let pane: PaneController
    do {
      pane = try PaneController(ghosttyApp: app)
    } catch {
      SmoovLog.error("PaneController init failed: \(error)")
      NSApp.terminate(nil)
      return
    }
    self.pane = pane

    let controller = MainWindowController(pane: pane)
    controller.showWindow(nil)
    self.windowController = controller
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}
