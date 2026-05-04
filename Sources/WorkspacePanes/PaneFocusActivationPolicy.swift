import Foundation

public enum PaneFocusActivationPolicy {
  public enum MouseDownFocusAction: Equatable {
    case passThrough
    case focusAndPassThrough
    case focusAndConsume
  }

  public static func mouseDownFocusAction(
    isAppActive: Bool,
    isWindowKey: Bool,
    isAlreadyFirstResponder: Bool
  ) -> MouseDownFocusAction {
    if isAlreadyFirstResponder {
      return .passThrough
    }

    if isAppActive && isWindowKey {
      return .focusAndConsume
    }

    return .focusAndPassThrough
  }

  public static func initialTerminalFocusStates(
    paneIds: [UUID],
    selectedPaneId: UUID
  ) -> [UUID: Bool] {
    Dictionary(
      uniqueKeysWithValues: paneIds.map { paneId in
        (paneId, paneId == selectedPaneId)
      })
  }
}
