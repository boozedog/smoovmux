import Combine
import Foundation
import WorkspaceTabs

@MainActor
final class WorkspaceTabManager: ObservableObject {
  @Published private var tabList = WorkspaceTabList()

  private let ghosttyApp: GhosttyApp
  private var panesByTabId: [UUID: PaneController] = [:]

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
    panesByTabId[tab.id] = PaneController(
      ghosttyApp: ghosttyApp,
      initialCwd: tab.cwd,
      onCwdChange: { [weak self] cwd in
        self?.tabList.updateCwd(cwd, for: tab.id)
      }
    )
    return tab
  }

  func selectTab(_ id: UUID) {
    tabList.selectTab(id)
  }

  func selectNextTab() {
    tabList.selectNextTab()
  }

  func selectPreviousTab() {
    tabList.selectPreviousTab()
  }

  func closeSelectedTab() {
    guard let selectedTabId else { return }
    closeTab(selectedTabId)
  }

  func closeTab(_ id: UUID) {
    guard tabList.closeTab(id) else { return }
    panesByTabId[id] = nil
  }
}
