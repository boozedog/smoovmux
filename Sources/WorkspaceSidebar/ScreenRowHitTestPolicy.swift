public enum ScreenRowHitTestPolicy {
  public static func overlayAcceptsHit(
    x: Double,
    rowWidth: Double,
    closeAffordanceWidth: Double,
    canClose: Bool,
    isHovering: Bool
  ) -> Bool {
    guard canClose, isHovering, closeAffordanceWidth > 0 else { return true }
    return x < rowWidth - closeAffordanceWidth
  }
}
