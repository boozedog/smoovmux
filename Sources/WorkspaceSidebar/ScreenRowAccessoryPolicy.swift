public enum ScreenRowAccessory: Equatable, Sendable {
  case shortcut
  case closeButton
  case indicator
  case empty
}

public enum ScreenRowAccessoryPolicy {
  public static func accessory(
    canClose: Bool,
    isHovering: Bool,
    showShortcut: Bool,
    hasIndicator: Bool
  ) -> ScreenRowAccessory {
    if showShortcut {
      return .shortcut
    }
    if canClose && isHovering {
      return .closeButton
    }
    if hasIndicator {
      return .indicator
    }
    return .empty
  }
}
