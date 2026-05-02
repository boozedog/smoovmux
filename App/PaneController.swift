import AppKit
import GhosttyKit
import SmoovLog
import WorkspacePanes

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
  private let onCwdChange: (URL) -> Void
  private var paneTree: WorkspacePaneTree
  private var surfaceViews: [SmoovSurfaceView] = []
  private var paneIdsBySurfaceView: [ObjectIdentifier: UUID] = [:]
  private weak var focusedSurfaceView: SmoovSurfaceView?

  init(ghosttyApp: GhosttyApp, initialCwd: URL? = nil, onCwdChange: @escaping (URL) -> Void = { _ in }) {
    self.ghosttyApp = ghosttyApp
    self.onCwdChange = onCwdChange
    self.paneTree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(cwd: initialCwd)))
    rootView.wantsLayer = true

    let surfaceView = makeSurfaceView(id: paneTree.selectedPaneId)
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
    guard let surfaceView = focusedSurfaceView,
      surfaceViews.count > 1,
      let paneId = paneIdsBySurfaceView[ObjectIdentifier(surfaceView)],
      paneTree.closePane(paneId)
    else { return }
    surfaceView.requestClosePane()
    collapse(surfaceView)
  }

  private enum SplitDirection {
    case right
    case down

    var paneTreeDirection: WorkspacePaneSplitDirection {
      switch self {
      case .right:
        return .right
      case .down:
        return .down
      }
    }
  }

  private func makeSurfaceView(id: UUID) -> SmoovSurfaceView {
    let surfaceView = SmoovSurfaceView(
      app: ghosttyApp,
      config: SmoovSurfaceView.Config(workingDirectory: cwd(for: id))
    )
    paneIdsBySurfaceView[ObjectIdentifier(surfaceView)] = id
    surfaceView.onFocus = { [weak self, weak surfaceView] in
      guard let self, let surfaceView else { return }
      focusedSurfaceView = surfaceView
      if let id = paneIdsBySurfaceView[ObjectIdentifier(surfaceView)] {
        paneTree.selectPane(id)
      }
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
    surfaceView.onCwdChanged = { [weak self, weak surfaceView] cwd in
      guard let self, let surfaceView,
        let id = paneIdsBySurfaceView[ObjectIdentifier(surfaceView)]
      else { return }
      paneTree.updateCwd(cwd, for: id)
      onCwdChange(cwd)
    }
    return surfaceView
  }

  private func cwd(for paneId: UUID) -> URL? {
    paneTree.leaves.first { $0.id == paneId }?.cwd
  }

  private func splitFocusedSurface(direction: SplitDirection) {
    guard let target = focusedSurfaceView,
      let targetId = paneIdsBySurfaceView[ObjectIdentifier(target)],
      let newPaneId = paneTree.splitPane(targetId, direction: direction.paneTreeDirection)
    else { return }
    let newSurfaceView = makeSurfaceView(id: newPaneId)
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

    scheduleBalanceSplits()

    DispatchQueue.main.async { [weak newSurfaceView] in
      guard let newSurfaceView, let window = newSurfaceView.window else { return }
      window.makeFirstResponder(newSurfaceView)
    }
  }

  private func collapse(_ surfaceView: SmoovSurfaceView) {
    surfaceViews.removeAll { $0 === surfaceView }
    paneIdsBySurfaceView[ObjectIdentifier(surfaceView)] = nil

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
    scheduleBalanceSplits()
    focusSelectedSurface()
  }

  private func scheduleBalanceSplits() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      rootView.layoutSubtreeIfNeeded()
      balanceSplits(in: rootView)
    }
  }

  private func balanceSplits(in view: NSView) {
    guard let splitView = view as? NSSplitView else {
      for subview in view.subviews {
        balanceSplits(in: subview)
      }
      return
    }

    splitView.layoutSubtreeIfNeeded()
    if splitView.arrangedSubviews.count == 2 {
      let first = splitView.arrangedSubviews[0]
      let second = splitView.arrangedSubviews[1]
      let firstWeight = balanceWeight(of: first, matching: splitView.isVertical)
      let secondWeight = balanceWeight(of: second, matching: splitView.isVertical)
      let totalWeight = firstWeight + secondWeight
      let length = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
      let availableLength = length - splitView.dividerThickness
      if totalWeight > 0, availableLength > 0 {
        let position = availableLength * CGFloat(firstWeight) / CGFloat(totalWeight)
        splitView.setPosition(position, ofDividerAt: 0)
      }
    }

    for subview in splitView.arrangedSubviews {
      balanceSplits(in: subview)
    }
  }

  private func balanceWeight(of view: NSView, matching isVertical: Bool) -> Int {
    guard let splitView = view as? NSSplitView, splitView.isVertical == isVertical else {
      return 1
    }
    return splitView.arrangedSubviews.reduce(0) { total, subview in
      total + balanceWeight(of: subview, matching: isVertical)
    }
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
