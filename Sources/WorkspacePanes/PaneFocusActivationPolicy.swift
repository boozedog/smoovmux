import Foundation

public enum PaneFocusActivationPolicy {
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
