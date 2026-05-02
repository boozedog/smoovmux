import AppKit
import GhosttyKit
import SmoovLog

/// Owns one workspace pane tree.
///
/// libghostty owns each pane PTY and launches the configured child process.
/// Leaving `SmoovSurfaceView.Config.command` nil asks libghostty to start the
/// user's normal login shell. tmux is intentionally not special-cased here:
/// users who want tmux can run `tmux` inside this terminal like any other TUI.
@MainActor
final class PaneController {
  /// The view the window controller hosts. Owned by this controller; its
  /// lifetime is tied to the tab/workspace.
  let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

  private let ghosttyApp: GhosttyApp
  private var surfaceViews: [SmoovSurfaceView] = []
  private weak var focusedSurfaceView: SmoovSurfaceView?

  init(ghosttyApp: GhosttyApp) {
    self.ghosttyApp = ghosttyApp
    rootView.wantsLayer = true

    let surfaceView = makeSurfaceView()
    surfaceViews = [surfaceView]
    focusedSurfaceView = surfaceView
    installRootSubview(surfaceView)
    SmoovLog.info("pane launched with default shell")
  }

  func splitRight() {
    splitFocusedSurface(direction: .right)
  }

  func splitDown() {
    splitFocusedSurface(direction: .down)
  }

  func closePane() {
    guard let surfaceView = focusedSurfaceView, surfaceViews.count > 1 else { return }
    surfaceView.requestClosePane()
    collapse(surfaceView)
  }

  private enum SplitDirection {
    case right
    case down
  }

  private func makeSurfaceView() -> SmoovSurfaceView {
    let surfaceView = SmoovSurfaceView(app: ghosttyApp, config: SmoovSurfaceView.Config())
    surfaceView.onFocus = { [weak self, weak surfaceView] in
      guard let surfaceView else { return }
      self?.focusedSurfaceView = surfaceView
    }
    surfaceView.onSplitRequested = { [weak self] direction in
      switch direction {
      case GHOSTTY_SPLIT_DIRECTION_RIGHT:
        self?.splitRight()
      case GHOSTTY_SPLIT_DIRECTION_DOWN:
        self?.splitDown()
      default:
        break
      }
    }
    surfaceView.onCloseRequested = { [weak self] in
      self?.closePane()
    }
    return surfaceView
  }

  private func splitFocusedSurface(direction: SplitDirection) {
    guard let target = focusedSurfaceView else { return }
    let newSurfaceView = makeSurfaceView()
    surfaceViews.append(newSurfaceView)

    let splitView = NSSplitView()
    splitView.isVertical = direction == .right
    splitView.dividerStyle = .thin

    replace(target, with: splitView)
    target.translatesAutoresizingMaskIntoConstraints = false
    newSurfaceView.translatesAutoresizingMaskIntoConstraints = false
    splitView.addArrangedSubview(target)
    splitView.addArrangedSubview(newSurfaceView)
    focusedSurfaceView = newSurfaceView

    DispatchQueue.main.async { [weak newSurfaceView] in
      guard let newSurfaceView, let window = newSurfaceView.window else { return }
      window.makeFirstResponder(newSurfaceView)
    }
  }

  private func collapse(_ surfaceView: SmoovSurfaceView) {
    surfaceViews.removeAll { $0 === surfaceView }

    guard let parentSplitView = surfaceView.superview as? NSSplitView else { return }
    let siblings = parentSplitView.arrangedSubviews.filter { $0 !== surfaceView }
    surfaceView.removeFromSuperview()

    guard siblings.count == 1, let sibling = siblings.first else {
      focusedSurfaceView = surfaceViews.last
      focusSelectedSurface()
      return
    }

    replace(parentSplitView, with: sibling)
    focusedSurfaceView = firstSurface(in: sibling) ?? surfaceViews.last
    focusSelectedSurface()
  }

  private func replace(_ oldView: NSView, with newView: NSView) {
    newView.translatesAutoresizingMaskIntoConstraints = false

    if oldView.superview === rootView {
      oldView.removeFromSuperview()
      installRootSubview(newView)
      return
    }

    guard let parentSplitView = oldView.superview as? NSSplitView,
      let index = parentSplitView.arrangedSubviews.firstIndex(of: oldView)
    else {
      return
    }

    oldView.removeFromSuperview()
    parentSplitView.insertArrangedSubview(newView, at: index)
  }

  private func installRootSubview(_ view: NSView) {
    view.translatesAutoresizingMaskIntoConstraints = false
    rootView.addSubview(view)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
      view.topAnchor.constraint(equalTo: rootView.topAnchor),
      view.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
    ])
  }

  private func firstSurface(in view: NSView) -> SmoovSurfaceView? {
    if let surfaceView = view as? SmoovSurfaceView {
      return surfaceView
    }
    for subview in view.subviews {
      if let surfaceView = firstSurface(in: subview) {
        return surfaceView
      }
    }
    return nil
  }

  private func focusSelectedSurface() {
    DispatchQueue.main.async { [weak self] in
      guard let surfaceView = self?.focusedSurfaceView, let window = surfaceView.window else { return }
      window.makeFirstResponder(surfaceView)
    }
  }
}
