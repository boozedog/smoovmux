import AppKit
import GhosttyKit
import SessionCore
import SmoovLog
import WorkspacePanes
import WorkspaceSidebar

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
  private let onCwdChange: (URL?) -> Void
  private let onStateChange: () -> Void
  private let onTitleChange: () -> Void
  private let onTerminalEvent: (TerminalScreenEvent) -> Void
  private var paneTree: WorkspacePaneTree
  private var commandsByPaneId: [UUID: String] = [:]
  private var titlesByPaneId: [UUID: String] = [:]
  private var surfaceViews: [SmoovSurfaceView] = []
  private var paneIdsBySurfaceView: [ObjectIdentifier: UUID] = [:]
  private weak var focusedSurfaceView: SmoovSurfaceView?
  private weak var activeSurfaceView: SmoovSurfaceView?
  private var zoomedPaneId: UUID?

  init(
    ghosttyApp: GhosttyApp,
    initialCwd: URL? = nil,
    command: String? = nil,
    onCwdChange: @escaping (URL?) -> Void = { _ in },
    onStateChange: @escaping () -> Void = {},
    onTitleChange: @escaping () -> Void = {},
    onTerminalEvent: @escaping (TerminalScreenEvent) -> Void = { _ in }
  ) {
    self.ghosttyApp = ghosttyApp
    self.onCwdChange = onCwdChange
    self.onStateChange = onStateChange
    self.onTitleChange = onTitleChange
    self.onTerminalEvent = onTerminalEvent
    self.paneTree = WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(cwd: initialCwd, command: command)))
    if let command {
      commandsByPaneId[paneTree.selectedPaneId] = command
    }
    rootView.wantsLayer = true

    let surfaceView = makeSurfaceView(id: paneTree.selectedPaneId)
    surfaceViews = [surfaceView]
    focusedSurfaceView = surfaceView
    installRootSubview(surfaceView)
    SmoovLog.info("pane launched with default shell")
  }

  init(
    ghosttyApp: GhosttyApp,
    paneTree: WorkspacePaneTree,
    onCwdChange: @escaping (URL?) -> Void = { _ in },
    onStateChange: @escaping () -> Void = {},
    onTitleChange: @escaping () -> Void = {},
    onTerminalEvent: @escaping (TerminalScreenEvent) -> Void = { _ in }
  ) {
    self.ghosttyApp = ghosttyApp
    self.onCwdChange = onCwdChange
    self.onStateChange = onStateChange
    self.onTitleChange = onTitleChange
    self.onTerminalEvent = onTerminalEvent
    self.paneTree = paneTree
    self.commandsByPaneId = Dictionary(
      uniqueKeysWithValues: paneTree.leaves.compactMap { leaf in
        leaf.command.map { (leaf.id, $0) }
      }
    )
    rootView.wantsLayer = true

    let view = makeView(for: paneTree.root)
    installRootSubview(view)
    focusSelectedSurface()
    SmoovLog.info("pane restored with default shell")
  }

  var snapshot: WorkspacePaneTree {
    paneTree
  }

  var selectedCwd: URL? {
    paneTree.selectedPane?.cwd
  }

  var isZoomed: Bool {
    zoomedPaneId != nil
  }

  var selectedTerminalTitle: String? {
    PanePresentationPolicy.selectedTerminalTitle(
      selectedPaneId: paneTree.selectedPaneId,
      titlesByPaneId: titlesByPaneId
    )
  }

  var selectedPaneCommand: String? {
    paneTree.selectedPane?.command
  }

  var windowTitle: String {
    PanePresentationPolicy.windowTitle(for: paneTree.selectedPane, homePath: NSHomeDirectory())
  }

  func splitRight(command: String? = nil) {
    splitFocusedSurface(direction: .right, command: command)
  }

  func splitDown(command: String? = nil) {
    splitFocusedSurface(direction: .down, command: command)
  }

  func toggleZoomSelectedPane() {
    if zoomedPaneId == paneTree.selectedPaneId {
      zoomedPaneId = nil
    } else {
      zoomedPaneId = paneTree.selectedPaneId
    }
    applyZoomState()
    focusSelectedSurface()
  }

  func closePane() {
    guard let surfaceView = focusedSurfaceView,
      surfaceViews.count > 1,
      let paneId = paneIdsBySurfaceView[ObjectIdentifier(surfaceView)],
      paneTree.closePane(paneId)
    else { return }
    if zoomedPaneId == paneId {
      zoomedPaneId = nil
    }
    surfaceView.requestClosePane()
    collapse(surfaceView)
    applyZoomState()
    onStateChange()
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
      config: SmoovSurfaceView.Config(command: launchCommand(for: id), workingDirectory: cwd(for: id))
    )
    paneIdsBySurfaceView[ObjectIdentifier(surfaceView)] = id
    surfaceView.onFocus = { [weak self, weak surfaceView] in
      guard let self, let surfaceView else { return }
      focusedSurfaceView = surfaceView
      if let id = paneIdsBySurfaceView[ObjectIdentifier(surfaceView)], paneTree.selectPane(id) {
        onCwdChange(cwd(for: id))
        onTitleChange()
        onStateChange()
      }
    }
    surfaceView.onFocusChanged = { [weak self, weak surfaceView] focused in
      guard let self, let surfaceView else { return }
      if focused {
        activeSurfaceView = surfaceView
      } else if activeSurfaceView === surfaceView {
        activeSurfaceView = nil
      }
      updateFocusRing()
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
    surfaceView.onTitleChanged = { [weak self, weak surfaceView] title in
      guard let self, let surfaceView,
        let id = paneIdsBySurfaceView[ObjectIdentifier(surfaceView)],
        titlesByPaneId[id] != title
      else { return }
      titlesByPaneId[id] = title
      if id == paneTree.selectedPaneId {
        onTitleChange()
      }
    }
    surfaceView.onCwdChanged = { [weak self, weak surfaceView] cwd in
      guard let self, let surfaceView,
        let id = paneIdsBySurfaceView[ObjectIdentifier(surfaceView)]
      else { return }
      paneTree.updateCwd(cwd, for: id)
      if id == paneTree.selectedPaneId {
        onCwdChange(cwd)
      }
      onStateChange()
    }
    surfaceView.onBell = { [weak self] in
      self?.onTerminalEvent(.bell)
    }
    surfaceView.onProgressChanged = { [weak self] progress in
      self?.onTerminalEvent(.progressChanged(progress))
    }
    surfaceView.onCommandFinished = { [weak self] exitCode in
      self?.onTerminalEvent(.commandFinished(exitCode: exitCode))
    }
    surfaceView.onChildExited = { [weak self] exitCode in
      self?.onTerminalEvent(.childExited(exitCode: exitCode))
    }
    surfaceView.onRendererHealthChanged = { [weak self] healthy in
      self?.onTerminalEvent(.rendererHealthChanged(healthy: healthy))
    }
    surfaceView.onDesktopNotification = { [weak self] notification in
      self?.onTerminalEvent(.desktopNotification(notification))
    }
    surfaceView.onMouseOverLink = { [weak self] url in
      self?.onTerminalEvent(.mouseOverLink(url))
    }
    surfaceView.onColorChanged = { [weak self] colorChange in
      self?.onTerminalEvent(.colorChanged(colorChange))
    }
    surfaceView.onConfigReloaded = { [weak self] soft in
      self?.onTerminalEvent(.configReloaded(soft: soft))
    }
    surfaceView.onConfigChanged = { [weak self] in
      self?.onTerminalEvent(.configChanged)
    }
    surfaceView.onSearchStarted = { [weak self] needle in
      self?.onTerminalEvent(.searchStarted(needle: needle))
    }
    surfaceView.onSearchEnded = { [weak self] in
      self?.onTerminalEvent(.searchEnded)
    }
    surfaceView.onSearchTotal = { [weak self] total in
      self?.onTerminalEvent(.searchTotal(total))
    }
    surfaceView.onSearchSelected = { [weak self] selected in
      self?.onTerminalEvent(.searchSelected(selected))
    }
    surfaceView.onScrollbarChanged = { [weak self] scrollbar in
      self?.onTerminalEvent(.scrollbarChanged(scrollbar))
    }
    return surfaceView
  }

  private func cwd(for paneId: UUID) -> URL? {
    paneTree.leaves.first { $0.id == paneId }?.cwd
  }

  private func launchCommand(for paneId: UUID) -> String? {
    commandsByPaneId[paneId] ?? DefaultShellSettings().launchCommand
  }

  private func splitFocusedSurface(direction: SplitDirection, command: String?) {
    if zoomedPaneId != nil {
      zoomedPaneId = nil
      applyZoomState()
    }
    guard let target = focusedSurfaceView,
      let targetId = paneIdsBySurfaceView[ObjectIdentifier(target)],
      let newPaneId = paneTree.splitPane(targetId, direction: direction.paneTreeDirection)
    else { return }
    if let command {
      commandsByPaneId[newPaneId] = command
      paneTree.updateCommand(command, for: newPaneId)
    }
    let newSurfaceView = makeSurfaceView(id: newPaneId)
    surfaceViews.append(newSurfaceView)
    onStateChange()

    let splitView = PaneSplitView()
    splitView.isVertical = direction == .right
    splitView.dividerStyle = .thin

    replace(target, with: splitView)
    target.translatesAutoresizingMaskIntoConstraints = false
    newSurfaceView.translatesAutoresizingMaskIntoConstraints = false
    splitView.addArrangedSubview(target)
    splitView.addArrangedSubview(newSurfaceView)
    focusedSurfaceView = newSurfaceView
    activeSurfaceView = newSurfaceView
    updateFocusRing()
    applyZoomState()

    scheduleBalanceSplits()

    DispatchQueue.main.async { [weak newSurfaceView] in
      guard let newSurfaceView, let window = newSurfaceView.window else { return }
      window.makeFirstResponder(newSurfaceView)
    }
  }

  private func makeView(for node: WorkspacePaneNode) -> NSView {
    switch node {
    case .leaf(let leaf):
      let surfaceView = makeSurfaceView(id: leaf.id)
      surfaceViews.append(surfaceView)
      if leaf.id == paneTree.selectedPaneId {
        focusedSurfaceView = surfaceView
      }
      return surfaceView
    case .split(let split):
      let splitView = PaneSplitView()
      splitView.isVertical = split.direction == .right
      splitView.dividerStyle = .thin
      splitView.addArrangedSubview(makeView(for: split.first))
      splitView.addArrangedSubview(makeView(for: split.second))
      scheduleBalanceSplits()
      return splitView
    }
  }

  private func collapse(_ surfaceView: SmoovSurfaceView) {
    surfaceViews.removeAll { $0 === surfaceView }
    if let paneId = paneIdsBySurfaceView[ObjectIdentifier(surfaceView)] {
      commandsByPaneId[paneId] = nil
      titlesByPaneId[paneId] = nil
    }
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
    updateFocusRing()
    applyZoomState()
    scheduleBalanceSplits()
    focusSelectedSurface()
  }

  private func applyZoomState() {
    applyZoomState(in: rootView)
    rootView.needsLayout = true
    rootView.layoutSubtreeIfNeeded()
    scheduleBalanceSplits()
  }

  @discardableResult
  private func applyZoomState(in view: NSView) -> Bool {
    guard let zoomedPaneId else {
      view.isHidden = false
      for subview in view.subviews {
        applyZoomState(in: subview)
      }
      return true
    }

    if let surfaceView = view as? SmoovSurfaceView {
      let containsZoomedPane = paneIdsBySurfaceView[ObjectIdentifier(surfaceView)] == zoomedPaneId
      surfaceView.isHidden = !containsZoomedPane
      return containsZoomedPane
    }

    if let splitView = view as? NSSplitView {
      var containsBySubview: [NSView: Bool] = [:]
      for subview in splitView.arrangedSubviews {
        containsBySubview[subview] = applyZoomState(in: subview)
      }
      for subview in splitView.arrangedSubviews {
        subview.isHidden = containsBySubview[subview] != true
      }
      splitView.adjustSubviews()
      DispatchQueue.main.async { [weak splitView] in
        guard let splitView else { return }
        self.expandZoomedSubview(in: splitView, containsBySubview: containsBySubview)
      }
      return containsBySubview.values.contains(true)
    }

    var containsZoomedPane = false
    for subview in view.subviews {
      containsZoomedPane = applyZoomState(in: subview) || containsZoomedPane
    }
    view.isHidden = !containsZoomedPane
    return containsZoomedPane
  }

  private func expandZoomedSubview(in splitView: NSSplitView, containsBySubview: [NSView: Bool]) {
    guard zoomedPaneId != nil, splitView.arrangedSubviews.count == 2 else { return }
    splitView.layoutSubtreeIfNeeded()
    let length = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
    guard length > splitView.dividerThickness else { return }
    let availableLength = length - splitView.dividerThickness
    if containsBySubview[splitView.arrangedSubviews[0]] == true {
      splitView.setPosition(availableLength, ofDividerAt: 0)
    } else if containsBySubview[splitView.arrangedSubviews[1]] == true {
      splitView.setPosition(0, ofDividerAt: 0)
    }
  }

  private func scheduleBalanceSplits() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      rootView.layoutSubtreeIfNeeded()
      balanceSplits(in: rootView)
    }
  }

  private func balanceSplits(in view: NSView) {
    if zoomedPaneId != nil {
      return
    }
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

  private func updateFocusRing() {
    for surfaceView in surfaceViews {
      surfaceView.wantsLayer = true
      let isActive = surfaceView === activeSurfaceView
      surfaceView.layer?.borderWidth = isActive ? 1 : 0
      surfaceView.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.95).cgColor
      surfaceView.layer?.shadowColor = NSColor.systemBlue.cgColor
      surfaceView.layer?.shadowOpacity = 0
      surfaceView.layer?.shadowRadius = 0
      surfaceView.layer?.shadowOffset = .zero
      surfaceView.layer?.masksToBounds = false
    }
  }

  private func focusSelectedSurface() {
    DispatchQueue.main.async { [weak self] in
      guard let self, let surfaceView = focusedSurfaceView, let window = surfaceView.window else { return }
      updateFocusRing()
      window.makeFirstResponder(surfaceView)
    }
  }
}

private final class PaneSplitView: NSSplitView {
  override func drawDivider(in rect: NSRect) {
    NSColor.black.setFill()
    rect.fill()
  }
}
