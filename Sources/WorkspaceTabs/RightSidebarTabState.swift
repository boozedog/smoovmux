import Foundation

public struct RightSidebarTabState<Pane> {
  private var panesByTabId: [UUID: Pane] = [:]
  private var gitRootsByTabId: [UUID: URL] = [:]
  private var messagesByTabId: [UUID: String] = [:]

  public init() {}

  public func pane(for tabId: UUID?) -> Pane? {
    guard let tabId else { return nil }
    return panesByTabId[tabId]
  }

  public func gitRoot(for tabId: UUID?) -> URL? {
    guard let tabId else { return nil }
    return gitRootsByTabId[tabId]
  }

  public func message(for tabId: UUID?) -> String? {
    guard let tabId else { return nil }
    return messagesByTabId[tabId]
  }

  public mutating func setPane(_ pane: Pane, gitRoot: URL, for tabId: UUID) {
    panesByTabId[tabId] = pane
    gitRootsByTabId[tabId] = gitRoot
    messagesByTabId[tabId] = nil
  }

  public mutating func setMessage(_ message: String?, for tabId: UUID) {
    guard let message else {
      clearMessage(for: tabId)
      return
    }
    messagesByTabId[tabId] = message
  }

  public mutating func clearMessage(for tabId: UUID) {
    messagesByTabId[tabId] = nil
  }

  public mutating func clearPane(keepingGitRoot gitRoot: URL? = nil, message: String?, for tabId: UUID) {
    panesByTabId[tabId] = nil
    gitRootsByTabId[tabId] = gitRoot
    setMessage(message, for: tabId)
  }

  public mutating func discardPane(for tabId: UUID) {
    panesByTabId[tabId] = nil
    gitRootsByTabId[tabId] = nil
    messagesByTabId[tabId] = nil
  }

  public mutating func discardAll() {
    panesByTabId.removeAll()
    gitRootsByTabId.removeAll()
    messagesByTabId.removeAll()
  }
}
