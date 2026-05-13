import Testing

@testable import WorkspaceSidebar

@Suite("Screen row hit test policy")
struct ScreenRowHitTestPolicyTests {
  @Test("close affordance area is excluded from drag overlay when closable and hovered")
  func closeAreaExcludedWhenClosableAndHovered() {
    #expect(
      ScreenRowHitTestPolicy.overlayAcceptsHit(
        x: 184,
        rowWidth: 200,
        closeAffordanceWidth: 32,
        canClose: true,
        isHovering: true
      ) == false)
  }

  @Test("drag overlay accepts body hits while close affordance is visible")
  func bodyAcceptedWhenCloseAffordanceVisible() {
    #expect(
      ScreenRowHitTestPolicy.overlayAcceptsHit(
        x: 120,
        rowWidth: 200,
        closeAffordanceWidth: 32,
        canClose: true,
        isHovering: true
      ))
  }

  @Test("drag overlay accepts trailing hits when close affordance is hidden")
  func trailingAcceptedWhenCloseAffordanceHidden() {
    #expect(
      ScreenRowHitTestPolicy.overlayAcceptsHit(
        x: 184,
        rowWidth: 200,
        closeAffordanceWidth: 32,
        canClose: true,
        isHovering: false
      ))
  }
}
