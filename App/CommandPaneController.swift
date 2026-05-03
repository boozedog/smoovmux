import AppKit
import GhosttyKit
import SmoovLog

@MainActor
final class CommandPaneController {
  let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 600))

  private let surfaceView: SmoovSurfaceView

  init(ghosttyApp: GhosttyApp, command: String, cwd: URL?) {
    rootView.wantsLayer = true
    surfaceView = SmoovSurfaceView(
      app: ghosttyApp,
      config: SmoovSurfaceView.Config(command: command, workingDirectory: cwd)
    )
    installSurfaceView()
    SmoovLog.info("command pane launched")
  }

  func focus() {
    DispatchQueue.main.async { [weak self] in
      guard let self, let window = surfaceView.window else { return }
      window.makeFirstResponder(surfaceView)
    }
  }

  private func installSurfaceView() {
    surfaceView.translatesAutoresizingMaskIntoConstraints = false
    rootView.addSubview(surfaceView)
    NSLayoutConstraint.activate([
      surfaceView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      surfaceView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      surfaceView.topAnchor.constraint(equalTo: rootView.topAnchor),
      surfaceView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
  }
}
