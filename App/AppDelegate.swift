import AppKit
import SmoovLog

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var windowController: MainWindowController?

	func applicationDidFinishLaunching(_ notification: Notification) {
		SmoovLog.info("smoovmux launched")
		let controller = MainWindowController()
		controller.showWindow(nil)
		windowController = controller
		NSApp.activate(ignoringOtherApps: true)
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		true
	}
}
