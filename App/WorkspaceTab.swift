import Combine
import Foundation
import WorkspacePanes
import WorkspaceState
import WorkspaceTabs

@MainActor
final class WorkspaceTabManager: ObservableObject {
  @Published private var tabList = WorkspaceTabList()

  private let ghosttyApp: GhosttyApp
  private var panesByTabId: [UUID: PaneController] = [:]
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

  init(ghosttyApp: GhosttyApp) {
    self.ghosttyApp = ghosttyApp
  }

  @discardableResult
  func addTab(select: Bool = true) -> WorkspaceTabRecord {
    let tab = tabList.addTab(cwd: tabList.lastKnownCwd, select: select)
    panesByTabId[tab.id] = makePaneController(tabId: tab.id, initialCwd: tab.cwd)
    onStateChange?()
    return tab
  }

  func restore(_ state: WorkspaceState) {
    panesByTabId.removeAll()
    tabList = WorkspaceTabList(tabs: state.tabs.map(\.record), selectedTabId: state.selectedTabId)
    for tab in state.tabs {
      panesByTabId[tab.record.id] = makePaneController(tabId: tab.record.id, paneTree: tab.paneTree)
    }
    onStateChange?()
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
      windowFrame: windowFrame
    )
  }

  func selectTab(_ id: UUID) {
    if tabList.selectTab(id) {
      onStateChange?()
    }
  }

  func selectNextTab() {
    tabList.selectNextTab()
    onStateChange?()
  }

  func selectPreviousTab() {
    tabList.selectPreviousTab()
    onStateChange?()
  }

  func closeSelectedTab() {
    guard let selectedTabId else { return }
    closeTab(selectedTabId)
  }

  func closeTab(_ id: UUID) {
    guard tabList.closeTab(id) else { return }
    panesByTabId[id] = nil
    onStateChange?()
  }

  private func makePaneController(tabId: UUID, initialCwd: URL?) -> PaneController {
    PaneController(
      ghosttyApp: ghosttyApp,
      initialCwd: initialCwd,
      onCwdChange: { [weak self] cwd in
        self?.tabList.updateCwd(cwd, for: tabId)
        self?.onStateChange?()
      },
      onStateChange: { [weak self] in
        self?.onStateChange?()
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
      },
      onStateChange: { [weak self] in
        self?.onStateChange?()
      }
    )
  }
}
