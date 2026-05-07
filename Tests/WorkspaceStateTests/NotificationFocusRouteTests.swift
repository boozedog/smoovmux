import Foundation
import Testing
import WorkspaceState

@Suite("Notification focus route")
struct NotificationFocusRouteTests {
  @Test("encodes and decodes privacy-safe window tab and pane identifiers")
  func encodesAndDecodesIdentifiers() {
    let route = NotificationFocusRoute(windowId: id(1), tabId: id(2), paneId: id(3))

    #expect(NotificationFocusRoute(userInfo: route.userInfo) == route)
    #expect(Set(route.userInfo.keys) == ["smoovmux.windowId", "smoovmux.tabId", "smoovmux.paneId"])
  }

  @Test("invalid userInfo does not produce a focus route")
  func invalidUserInfoFailsClosed() {
    #expect(NotificationFocusRoute(userInfo: [:]) == nil)
    #expect(NotificationFocusRoute(userInfo: ["smoovmux.windowId": "not-a-uuid"]) == nil)
  }
}

private func id(_ value: UInt8) -> UUID {
  UUID(uuid: (value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
