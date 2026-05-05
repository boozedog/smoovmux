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
  var defaultChoice: PaneLaunchChoice = .shell
}

@MainActor
final class WorkspaceTabManager: ObservableObject {
  @Published private var tabList = WorkspaceTabList()
  @Published var launcherPresentation: PaneLauncherPresentation?
  @Published var leftSidebarState = WorkspaceLeftSidebarState()
  @Published var rightSidebarState = WorkspaceRightSidebarState()
  @Published private var rightSidebarTabs = RightSidebarTabState<CommandPaneController>()
  @Published private var activePaneChrome = PaneChromeState()
  @Published private(set) var terminalStatusesByTabId: [UUID: TerminalScreenStatus] = [:]

  private let ghosttyApp: GhosttyApp
  private var panesByTabId: [UUID: PaneController] = [:]
  private let gitRootResolver = GitRootResolver()
  private var rightSidebarRefreshTask: Task<Void, Never>?
  private var rightSidebarAutoOpenTask: Task<Void, Never>?
  private var commandSuccessClearTasksByTabId: [UUID: Task<Void, Never>] = [:]
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

  var rightSidebarPane: CommandPaneController? {
    rightSidebarTabs.pane(for: selectedTabId)
  }

  var rightSidebarMessage: String? {
    rightSidebarTabs.message(for: selectedTabId)
  }

  var selectedTabTitle: String {
    tabList.selectedTab?.title ?? "Terminal"
  }

  var selectedPaneTitle: String {
    selectedPane?.windowTitle ?? selectedTabTitle
  }

  var topBarTitle: String {
    activePaneChrome.title(loginShellPath: loginShellPath, homePath: NSHomeDirectory())
  }

  var selectedPaneCwdDisplay: String {
    activePaneChrome.cwdDisplay(homePath: NSHomeDirectory())
  }

  var selectedPaneCommandKind: String {
    activePaneChrome.commandKind(loginShellPath: loginShellPath)
  }

  private var loginShellPath: String {
    DefaultShellSettings().launchCommand ?? DefaultShellPolicy.systemDefaultShellPath()
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
    updateActivePaneChrome()
    onStateChange?()
    return tab
  }

  func restore(_ state: WorkspaceState) {
    panesByTabId.removeAll()
    rightSidebarTabs.discardAll()
    tabList = WorkspaceTabList(tabs: state.tabs.map(\.record), selectedTabId: state.selectedTabId)
    leftSidebarState = state.leftSidebar
    rightSidebarState = state.rightSidebar
    for tab in state.tabs {
      panesByTabId[tab.record.id] = makePaneController(tabId: tab.record.id, paneTree: tab.paneTree)
    }
    updateSelectedTabCwd()
    updateActivePaneChrome()
    onStateChange?()
    if rightSidebarState.isOpen {
      refreshRightSidebar(forceRestart: false)
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
    launcherPresentation = PaneLauncherPresentation(action: resolvedAction, defaultChoice: defaultLauncherChoice())
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
      clearBellAttention(for: id)
      updateSelectedTabCwd()
      updateActivePaneChrome()
      onStateChange?()
      handleActiveCwdChanged()
    }
  }

  func selectNextTab() {
    tabList.selectNextTab()
    if let selectedTabId {
      clearBellAttention(for: selectedTabId)
    }
    updateSelectedTabCwd()
    updateActivePaneChrome()
    onStateChange?()
    handleActiveCwdChanged()
  }

  func selectPreviousTab() {
    tabList.selectPreviousTab()
    if let selectedTabId {
      clearBellAttention(for: selectedTabId)
    }
    updateSelectedTabCwd()
    updateActivePaneChrome()
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
    rightSidebarTabs.discardPane(for: id)
    terminalStatusesByTabId[id] = nil
    commandSuccessClearTasksByTabId[id]?.cancel()
    commandSuccessClearTasksByTabId[id] = nil
    updateActivePaneChrome()
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
      refreshRightSidebar(forceRestart: false)
    } else {
      rightSidebarRefreshTask?.cancel()
      rightSidebarRefreshTask = nil
    }
    onStateChange?()
  }

  func refreshRightSidebar(forceRestart: Bool = true) {
    guard rightSidebarState.isOpen else { return }
    guard let tabId = selectedTabId else { return }
    rightSidebarRefreshTask?.cancel()
    rightSidebarTabs.setMessage("Finding git repo…", for: tabId)
    let cwd = activeCwd
    rightSidebarRefreshTask = Task { [weak self] in
      guard let self else { return }
      await resolveAndOpenRightSidebar(cwd: cwd, tabId: tabId, forceRestart: forceRestart)
    }
  }

  private func handleActiveCwdChanged() {
    if rightSidebarState.isOpen {
      refreshRightSidebar(forceRestart: false)
    } else {
      autoOpenRightSidebarIfGitRepo()
    }
  }

  private func autoOpenRightSidebarIfGitRepo() {
    guard let tabId = selectedTabId, let cwd = activeCwd else { return }
    rightSidebarAutoOpenTask?.cancel()
    rightSidebarAutoOpenTask = Task { [weak self] in
      guard let self else { return }
      let gitRoot: URL?
      do {
        gitRoot = try await gitRootResolver.resolve(cwd: cwd)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      guard
        RightSidebarAutoOpenPolicy.shouldOpen(
          isSidebarOpen: rightSidebarState.isOpen,
          requestedCwd: cwd,
          currentActiveCwd: activeCwd,
          resolvedGitRoot: gitRoot
        ),
        let gitRoot
      else { return }

      rightSidebarState.isOpen = true
      onStateChange?()
      await openRightSidebar(gitRoot: gitRoot, tabId: tabId, forceRestart: false)
    }
  }

  private func resolveAndOpenRightSidebar(cwd: URL?, tabId: UUID, forceRestart: Bool) async {
    guard let cwd else {
      rightSidebarTabs.clearPane(message: "No active directory", for: tabId)
      return
    }

    let gitRoot: URL?
    do {
      gitRoot = try await gitRootResolver.resolve(cwd: cwd)
    } catch {
      rightSidebarTabs.clearPane(message: "Unable to find git", for: tabId)
      return
    }

    guard !Task.isCancelled else { return }
    guard let gitRoot else {
      rightSidebarTabs.clearPane(message: "Not a git repository", for: tabId)
      return
    }

    await openRightSidebar(gitRoot: gitRoot, tabId: tabId, forceRestart: forceRestart)
  }

  private func openRightSidebar(gitRoot: URL, tabId: UUID, forceRestart: Bool) async {
    let lazygitURL: URL
    do {
      lazygitURL = try BinaryResolver.resolve("lazygit")
    } catch {
      rightSidebarTabs.clearPane(
        keepingGitRoot: gitRoot,
        message: "lazygit not found\nInstall with: brew install lazygit",
        for: tabId
      )
      return
    }

    guard
      RightSidebarRefreshPolicy.shouldOpenPane(
        currentGitRoot: rightSidebarTabs.gitRoot(for: tabId),
        requestedGitRoot: gitRoot,
        hasExistingPane: rightSidebarTabs.pane(for: tabId) != nil,
        forceRestart: forceRestart
      )
    else {
      rightSidebarTabs.clearMessage(for: tabId)
      return
    }

    rightSidebarTabs.setPane(
      CommandPaneController(
        ghosttyApp: ghosttyApp,
        command: DefaultShellSettings().wrappedExecutableLaunchCommand(executablePath: lazygitURL.path),
        cwd: gitRoot
      ),
      gitRoot: gitRoot,
      for: tabId
    )
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

    switch event {
    case .commandFinished(exitCode: 0):
      scheduleSuccessfulCommandClear(for: tabId)
    case .commandFinished:
      commandSuccessClearTasksByTabId[tabId]?.cancel()
      commandSuccessClearTasksByTabId[tabId] = nil
    default:
      break
    }
  }

  private func clearBellAttention(for tabId: UUID) {
    var status = terminalStatus(for: tabId)
    status.clearBellAttention()
    terminalStatusesByTabId[tabId] = status
  }

  private func scheduleSuccessfulCommandClear(for tabId: UUID) {
    commandSuccessClearTasksByTabId[tabId]?.cancel()
    commandSuccessClearTasksByTabId[tabId] = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      await MainActor.run { [weak self] in
        guard let self else { return }
        var status = terminalStatus(for: tabId)
        status.clearSuccessfulCommandFinished()
        terminalStatusesByTabId[tabId] = status
        commandSuccessClearTasksByTabId[tabId] = nil
      }
    }
  }

  private func updateActivePaneChrome() {
    activePaneChrome = PaneChromeState(
      command: selectedPane?.selectedPaneCommand,
      terminalTitle: selectedPane?.selectedTerminalTitle,
      cwd: activeCwd
    )
  }

  private func defaultLauncherChoice() -> PaneLaunchChoice {
    switch DefaultLauncherSettings().choice {
    case .shell:
      return .shell
    case .pi:
      return .pi
    case .codex:
      return .codex
    case .claude:
      return .claude
    case .custom(let command):
      return .custom(command)
    }
  }

  private func makePaneController(tabId: UUID, initialCwd: URL?, command: String? = nil) -> PaneController {
    PaneController(
      ghosttyApp: ghosttyApp,
      initialCwd: initialCwd,
      command: command,
      onCwdChange: { [weak self] cwd in
        self?.tabList.updateCwd(cwd, for: tabId)
        self?.updateActivePaneChrome()
        self?.onStateChange?()
        self?.handleActiveCwdChanged()
      },
      onStateChange: { [weak self] in
        self?.updateActivePaneChrome()
        self?.onStateChange?()
      },
      onTitleChange: { [weak self] in
        self?.updateActivePaneChrome()
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
        self?.updateActivePaneChrome()
        self?.onStateChange?()
        self?.handleActiveCwdChanged()
      },
      onStateChange: { [weak self] in
        self?.updateActivePaneChrome()
        self?.onStateChange?()
      },
      onTitleChange: { [weak self] in
        self?.updateActivePaneChrome()
      },
      onTerminalEvent: { [weak self] event in
        self?.applyTerminalEvent(event, for: tabId)
      }
    )
  }
}
