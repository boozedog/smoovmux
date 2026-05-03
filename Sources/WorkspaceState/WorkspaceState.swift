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

public struct AppWorkspaceState: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public struct Window: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var workspace: WorkspaceState

    public init(id: UUID = UUID(), workspace: WorkspaceState) {
      self.id = id
      self.workspace = workspace
    }
  }

  public var schemaVersion: Int
  public var windows: [Window]
  public var selectedWindowId: UUID?

  public init(windows: [Window], selectedWindowId: UUID?) {
    self.schemaVersion = Self.currentSchemaVersion
    self.windows = windows
    self.selectedWindowId =
      selectedWindowId.flatMap { id in
        windows.contains { $0.id == id } ? id : nil
      } ?? windows.first?.id
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
    let windows = try container.decode([Window].self, forKey: .windows)
    let selectedWindowId = try container.decodeIfPresent(UUID.self, forKey: .selectedWindowId)
    self.init(windows: windows, selectedWindowId: selectedWindowId)
    self.schemaVersion = schemaVersion
  }

  public static func empty() -> Self {
    Self(windows: [], selectedWindowId: nil)
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
  public var selectedTabId: UUID?
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
    self.schemaVersion = Self.currentSchemaVersion
    self.tabs = tabs
    self.selectedTabId =
      selectedTabId.flatMap { id in
        tabs.contains { $0.record.id == id } ? id : nil
      } ?? tabs.first?.record.id
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

}
