import Foundation

public struct WorkspaceTabRecord: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var title: String

  public init(id: UUID = UUID(), title: String) {
    self.id = id
    self.title = title
  }
}

public struct WorkspaceTabList: Equatable, Sendable {
  public private(set) var tabs: [WorkspaceTabRecord]
  public private(set) var selectedTabId: UUID?

  public var selectedTab: WorkspaceTabRecord? {
    guard let selectedTabId else { return nil }
    return tabs.first { $0.id == selectedTabId }
  }

  public init(tabs: [WorkspaceTabRecord] = [], selectedTabId: UUID? = nil) {
    self.tabs = tabs
    self.selectedTabId =
      selectedTabId.flatMap { id in
        tabs.contains(where: { $0.id == id }) ? id : nil
      } ?? tabs.first?.id
  }

  @discardableResult
  public mutating func addTab(
    id: UUID = UUID(),
    title: String? = nil,
    select: Bool = true
  ) -> WorkspaceTabRecord {
    let tab = WorkspaceTabRecord(
      id: id,
      title: title ?? "Terminal \(tabs.count + 1)"
    )
    tabs.append(tab)
    if select || selectedTabId == nil {
      selectedTabId = tab.id
    }
    return tab
  }

  @discardableResult
  public mutating func selectTab(_ id: UUID) -> Bool {
    guard tabs.contains(where: { $0.id == id }) else { return false }
    selectedTabId = id
    return true
  }

  public mutating func selectNextTab() {
    selectTab(offset: 1)
  }

  public mutating func selectPreviousTab() {
    selectTab(offset: -1)
  }

  @discardableResult
  public mutating func closeTab(_ id: UUID) -> Bool {
    guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
    let wasSelected = selectedTabId == id
    tabs.remove(at: index)

    guard wasSelected else { return true }
    let nextIndex = min(index, tabs.count - 1)
    selectedTabId = tabs[nextIndex].id
    return true
  }

  private mutating func selectTab(offset: Int) {
    guard !tabs.isEmpty else { return }
    guard let currentId = selectedTabId, let currentIndex = tabs.firstIndex(where: { $0.id == currentId }) else {
      selectedTabId = tabs[0].id
      return
    }

    let nextIndex = (currentIndex + offset + tabs.count) % tabs.count
    selectedTabId = tabs[nextIndex].id
  }
}
