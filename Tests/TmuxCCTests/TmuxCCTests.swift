import Testing

@testable import TmuxCC

@Suite("TmuxCC namespace")
struct TmuxCCTests {
  @Test func controlModeFlag() {
    #expect(TmuxCC.controlModeFlag == "-CC")
  }
}
