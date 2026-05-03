import Foundation
import Testing
import WorkspaceSidebar

@Suite("Workspace right sidebar state")
struct WorkspaceSidebarStateTests {
  @Test("defaults closed with standard width")
  func defaultState() {
    let state = WorkspaceRightSidebarState()

    #expect(state.isOpen == false)
    #expect(state.width == 320)
  }

  @Test("width clamps to supported range")
  func widthClamps() {
    #expect(WorkspaceRightSidebarState(width: 100).width == 240)
    #expect(WorkspaceRightSidebarState(width: 700).width == 640)
    #expect(WorkspaceRightSidebarState(width: 380).width == 380)
  }

  @Test("codable round trip")
  func codableRoundTrip() throws {
    let state = WorkspaceRightSidebarState(isOpen: true, width: 380)

    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(WorkspaceRightSidebarState.self, from: data)

    #expect(decoded == state)
  }
}
