import Foundation
import WorkspacePanes
import WorkspaceSidebar
import WorkspaceTabs

public struct WorkspaceWindowFrame: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public struct WorkspaceState: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public struct Tab: Codable, Equatable, Sendable {
    public var record: WorkspaceTabRecord
    public var paneTree: WorkspacePaneTree

    public init(record: WorkspaceTabRecord, paneTree: WorkspacePaneTree) {
      self.record = record
      self.paneTree = paneTree
    }
  }

  public var schemaVersion: Int
  public var tabs: [Tab]
  public var selectedTabId: UUID
  public var windowFrame: WorkspaceWindowFrame?
  public var leftSidebar: WorkspaceLeftSidebarState
  public var rightSidebar: WorkspaceRightSidebarState

  public init(
    tabs: [Tab],
    selectedTabId: UUID?,
    windowFrame: WorkspaceWindowFrame?,
    leftSidebar: WorkspaceLeftSidebarState = WorkspaceLeftSidebarState(),
    rightSidebar: WorkspaceRightSidebarState = WorkspaceRightSidebarState()
  ) {
    let normalizedTabs = tabs.isEmpty ? [Self.defaultTab()] : tabs
    self.schemaVersion = Self.currentSchemaVersion
    self.tabs = normalizedTabs
    self.selectedTabId =
      selectedTabId.flatMap { id in
        normalizedTabs.contains { $0.record.id == id } ? id : nil
      } ?? normalizedTabs[0].record.id
    self.windowFrame = windowFrame
    self.leftSidebar = leftSidebar
    self.rightSidebar = rightSidebar
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
    let tabs = try container.decodeIfPresent([Tab].self, forKey: .tabs) ?? []
    let selectedTabId = try container.decodeIfPresent(UUID.self, forKey: .selectedTabId)
    let windowFrame = try container.decodeIfPresent(WorkspaceWindowFrame.self, forKey: .windowFrame)
    let leftSidebar =
      try container.decodeIfPresent(WorkspaceLeftSidebarState.self, forKey: .leftSidebar)
      ?? WorkspaceLeftSidebarState()
    let rightSidebar =
      try container.decodeIfPresent(WorkspaceRightSidebarState.self, forKey: .rightSidebar)
      ?? WorkspaceRightSidebarState()
    self.init(
      tabs: tabs,
      selectedTabId: selectedTabId,
      windowFrame: windowFrame,
      leftSidebar: leftSidebar,
      rightSidebar: rightSidebar
    )
    self.schemaVersion = schemaVersion
  }

  public static func empty() -> Self {
    Self(tabs: [], selectedTabId: nil, windowFrame: nil)
  }

  private static func defaultTab() -> Tab {
    let tree = WorkspacePaneTree()
    let record = WorkspaceTabRecord(id: UUID(), title: "Terminal 1", cwd: nil, usesAutomaticTitle: true)
    return Tab(record: record, paneTree: tree)
  }
}
