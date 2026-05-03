import Combine
import Foundation
import PaneLauncher
import SessionCore
import WorkspacePanes
import WorkspaceSidebar
import WorkspaceState
import WorkspaceTabs

struct PaneLauncherPresentation: Identifiable, Equatable {
  let id = UUID()
  var action: PaneLaunchAction
}

@MainActor
final class WorkspaceTabManager: ObservableObject {
  @Published private var tabList = WorkspaceTabList()
  @Published var launcherPresentation: PaneLauncherPresentation?
  @Published var leftSidebarState = WorkspaceLeftSidebarState()
  @Published var rightSidebarState = WorkspaceRightSidebarState()
  @Published private(set) var rightSidebarPane: CommandPaneController?
  @Published private(set) var rightSidebarMessage: String?
  @Published private(set) var activePaneTitle: String?
  @Published private(set) var terminalStatusesByTabId: [UUID: TerminalScreenStatus] = [:]

  private let ghosttyApp: GhosttyApp
  private var panesByTabId: [UUID: PaneController] = [:]
  private let gitRootResolver = GitRootResolver()
  private var currentRightSidebarGitRoot: URL?
  private var rightSidebarRefreshTask: Task<Void, Never>?
  private var rightSidebarAutoOpenTask: Task<Void, Never>?
  var onStateChange: (() -> Void)?

  var tabs: [WorkspaceTabRecord] {
    tabList.tabs
  }

  var selectedTabId: UUID? {
    tabList.selectedTabId
  }

  var selectedPane: PaneController? {
    guard let selectedTabId else { return nil }
    return panesByTabId[selectedTabId]
  }

  var selectedTabTitle: String {
    tabList.selectedTab?.title ?? "Terminal"
  }

  var selectedPaneTitle: String {
    selectedPane?.windowTitle ?? selectedTabTitle
  }

  var topBarTitle: String {
    PaneChromeTitlePolicy.title(
      command: selectedPane?.selectedPaneCommand,
      terminalTitle: activePaneTitle,
      loginShellPath: loginShellPath
    )
  }

  var selectedPaneCwdDisplay: String {
    PaneChromeTitlePolicy.cwdDisplay(cwd: activeCwd, homePath: NSHomeDirectory())
  }

  var selectedPaneCommandKind: String {
    guard let command = selectedPane?.selectedPaneCommand else {
      return PaneChromeTitlePolicy.executableName(fromPath: loginShellPath, fallback: "shell")
    }
    return PaneChromeTitlePolicy.commandName(command)
  }

  private var loginShellPath: String {
    ProcessInfo.processInfo.environment["SHELL"] ?? "shell"
  }

  var selectedPaneIsZoomed: Bool {
    selectedPane?.isZoomed ?? false
  }

  var activeCwd: URL? {
    selectedPane?.selectedCwd ?? tabList.selectedTab?.cwd
  }

  init(ghosttyApp: GhosttyApp) {
    self.ghosttyApp = ghosttyApp
  }

  @discardableResult
  func addTab(select: Bool = true, command: String? = nil) -> WorkspaceTabRecord {
    let tab = tabList.addTab(cwd: tabList.lastKnownCwd, select: select)
    panesByTabId[tab.id] = makePaneController(tabId: tab.id, initialCwd: tab.cwd, command: command)
    updateActivePaneTitle()
    onStateChange?()
    return tab
  }

  func restore(_ state: WorkspaceState) {
    panesByTabId.removeAll()
    tabList = WorkspaceTabList(tabs: state.tabs.map(\.record), selectedTabId: state.selectedTabId)
    leftSidebarState = state.leftSidebar
    rightSidebarState = state.rightSidebar
    for tab in state.tabs {
      panesByTabId[tab.record.id] = makePaneController(tabId: tab.record.id, paneTree: tab.paneTree)
    }
    updateSelectedTabCwd()
    updateActivePaneTitle()
    onStateChange?()
    if rightSidebarState.isOpen {
      refreshRightSidebar()
    }
  }

  func snapshot(windowFrame: WorkspaceWindowFrame?) -> WorkspaceState {
    WorkspaceState(
      tabs: tabList.tabs.map { tab in
        WorkspaceState.Tab(
          record: tab,
          paneTree: panesByTabId[tab.id]?.snapshot ?? WorkspacePaneTree(root: .leaf(WorkspacePaneLeaf(cwd: tab.cwd)))
        )
      },
      selectedTabId: tabList.selectedTabId,
      windowFrame: windowFrame,
      leftSidebar: leftSidebarState,
      rightSidebar: rightSidebarState
    )
  }

  func showLauncher(action: PaneLaunchAction = .newTab) {
    let resolvedAction = selectedPane == nil && action != .newTab ? .newTab : action
    launcherPresentation = PaneLauncherPresentation(action: resolvedAction)
  }

  func dismissLauncher() {
    launcherPresentation = nil
  }

  func toggleSelectedPaneZoom() {
    selectedPane?.toggleZoomSelectedPane()
    objectWillChange.send()
  }

  func launch(_ request: PaneLaunchRequest) {
    switch request.action {
    case .newTab:
      addTab(command: request.command)
    case .splitRight:
      selectedPane?.splitRight(command: request.command)
    case .splitDown:
      selectedPane?.splitDown(command: request.command)
    }
    dismissLauncher()
  }

  func selectTab(_ id: UUID) {
    if tabList.selectTab(id) {
      updateSelectedTabCwd()
      updateActivePaneTitle()
      onStateChange?()
      handleActiveCwdChanged()
    }
  }

  func selectNextTab() {
    tabList.selectNextTab()
    updateSelectedTabCwd()
    updateActivePaneTitle()
    onStateChange?()
    handleActiveCwdChanged()
  }

  func selectPreviousTab() {
    tabList.selectPreviousTab()
    updateSelectedTabCwd()
    updateActivePaneTitle()
    onStateChange?()
    handleActiveCwdChanged()
  }

  func closeSelectedTab() {
    guard let selectedTabId else { return }
    closeTab(selectedTabId)
  }

  func closeTab(_ id: UUID) {
    guard tabList.closeTab(id) else { return }
    panesByTabId[id] = nil
    terminalStatusesByTabId[id] = nil
    onStateChange?()
    handleActiveCwdChanged()
  }

  func toggleLeftSidebar() {
    leftSidebarState.isOpen.toggle()
    onStateChange?()
  }

  func setRightSidebarWidth(_ width: Double) {
    rightSidebarState.setWidth(width)
    onStateChange?()
  }

  func toggleRightSidebar() {
    rightSidebarAutoOpenTask?.cancel()
    rightSidebarAutoOpenTask = nil
    rightSidebarState.isOpen.toggle()
    if rightSidebarState.isOpen {
      refreshRightSidebar()
    } else {
      rightSidebarRefreshTask?.cancel()
      rightSidebarRefreshTask = nil
      currentRightSidebarGitRoot = nil
      rightSidebarPane = nil
      rightSidebarMessage = nil
    }
    onStateChange?()
  }

  func refreshRightSidebar() {
    guard rightSidebarState.isOpen else { return }
    rightSidebarRefreshTask?.cancel()
    rightSidebarMessage = "Finding git repo…"
    let cwd = activeCwd
    rightSidebarRefreshTask = Task { [weak self] in
      guard let self else { return }
      await resolveAndOpenRightSidebar(cwd: cwd)
    }
  }

  private func handleActiveCwdChanged() {
    if rightSidebarState.isOpen {
      refreshRightSidebar()
    } else {
      autoOpenRightSidebarIfGitRepo()
    }
  }

  private func autoOpenRightSidebarIfGitRepo() {
    guard let cwd = activeCwd else { return }
    rightSidebarAutoOpenTask?.cancel()
    rightSidebarAutoOpenTask = Task { [weak self] in
      guard let self else { return }
      let gitRoot: URL?
      do {
        gitRoot = try await gitRootResolver.resolve(cwd: cwd)
      } catch {
        return
      }
      guard !Task.isCancelled, let gitRoot else { return }
      guard rightSidebarState.isOpen == false else { return }
      guard activeCwd?.standardizedFileURL == cwd.standardizedFileURL else { return }

      rightSidebarState.isOpen = true
      onStateChange?()
      await openRightSidebar(gitRoot: gitRoot)
    }
  }

  private func resolveAndOpenRightSidebar(cwd: URL?) async {
    guard let cwd else {
      rightSidebarPane = nil
      currentRightSidebarGitRoot = nil
      rightSidebarMessage = "No active directory"
      return
    }

    let gitRoot: URL?
    do {
      gitRoot = try await gitRootResolver.resolve(cwd: cwd)
    } catch {
      rightSidebarPane = nil
      currentRightSidebarGitRoot = nil
      rightSidebarMessage = "Unable to find git"
      return
    }

    guard !Task.isCancelled else { return }
    guard let gitRoot else {
      rightSidebarPane = nil
      currentRightSidebarGitRoot = nil
      rightSidebarMessage = "Not a git repository"
      return
    }

    await openRightSidebar(gitRoot: gitRoot)
  }

  private func openRightSidebar(gitRoot: URL) async {
    let lazygitURL: URL
    do {
      lazygitURL = try BinaryResolver.resolve("lazygit")
    } catch {
      rightSidebarPane = nil
      currentRightSidebarGitRoot = gitRoot
      rightSidebarMessage = "lazygit not found\nInstall with: brew install lazygit"
      return
    }

    if currentRightSidebarGitRoot?.standardizedFileURL == gitRoot.standardizedFileURL, rightSidebarPane != nil {
      rightSidebarMessage = nil
      return
    }

    currentRightSidebarGitRoot = gitRoot
    rightSidebarMessage = nil
    rightSidebarPane = CommandPaneController(ghosttyApp: ghosttyApp, command: lazygitURL.path, cwd: gitRoot)
  }

  private func updateSelectedTabCwd() {
    guard let selectedTabId else { return }
    tabList.updateCwd(panesByTabId[selectedTabId]?.selectedCwd, for: selectedTabId)
  }

  func terminalStatus(for tabId: UUID) -> TerminalScreenStatus {
    terminalStatusesByTabId[tabId] ?? TerminalScreenStatus()
  }

  private func applyTerminalEvent(_ event: TerminalScreenEvent, for tabId: UUID) {
    var status = terminalStatus(for: tabId)
    status.apply(event)
    terminalStatusesByTabId[tabId] = status
  }

  private func updateActivePaneTitle() {
    activePaneTitle = selectedPane?.selectedTerminalTitle
  }

  private func makePaneController(tabId: UUID, initialCwd: URL?, command: String? = nil) -> PaneController {
    PaneController(
      ghosttyApp: ghosttyApp,
      initialCwd: initialCwd,
      command: command,
      onCwdChange: { [weak self] cwd in
        self?.tabList.updateCwd(cwd, for: tabId)
        self?.onStateChange?()
        self?.handleActiveCwdChanged()
      },
      onStateChange: { [weak self] in
        self?.onStateChange?()
      },
      onTitleChange: { [weak self] in
        self?.updateActivePaneTitle()
      },
      onTerminalEvent: { [weak self] event in
        self?.applyTerminalEvent(event, for: tabId)
      }
    )
  }

  private func makePaneController(tabId: UUID, paneTree: WorkspacePaneTree) -> PaneController {
    PaneController(
      ghosttyApp: ghosttyApp,
      paneTree: paneTree,
      onCwdChange: { [weak self] cwd in
        self?.tabList.updateCwd(cwd, for: tabId)
        self?.onStateChange?()
        self?.handleActiveCwdChanged()
      },
      onStateChange: { [weak self] in
        self?.onStateChange?()
      },
      onTitleChange: { [weak self] in
        self?.updateActivePaneTitle()
      },
      onTerminalEvent: { [weak self] event in
        self?.applyTerminalEvent(event, for: tabId)
      }
    )
  }
}
