import Foundation

public struct NotificationFocusRoute: Equatable, Sendable {
  public static let windowIdKey = "smoovmux.windowId"
  public static let tabIdKey = "smoovmux.tabId"
  public static let paneIdKey = "smoovmux.paneId"

  public var windowId: UUID
  public var tabId: UUID
  public var paneId: UUID

  public init(windowId: UUID, tabId: UUID, paneId: UUID) {
    self.windowId = windowId
    self.tabId = tabId
    self.paneId = paneId
  }

  public init?(userInfo: [AnyHashable: Any]) {
    guard
      let windowId = Self.uuid(for: Self.windowIdKey, in: userInfo),
      let tabId = Self.uuid(for: Self.tabIdKey, in: userInfo),
      let paneId = Self.uuid(for: Self.paneIdKey, in: userInfo)
    else { return nil }

    self.init(windowId: windowId, tabId: tabId, paneId: paneId)
  }

  public var userInfo: [String: String] {
    [
      Self.windowIdKey: windowId.uuidString,
      Self.tabIdKey: tabId.uuidString,
      Self.paneIdKey: paneId.uuidString,
    ]
  }

  private static func uuid(for key: String, in userInfo: [AnyHashable: Any]) -> UUID? {
    guard let rawValue = userInfo[key] as? String else { return nil }
    return UUID(uuidString: rawValue)
  }
}
