import Foundation
import Testing
import WorkspacePanes

@Suite("Pane focus activation policy")
struct PaneFocusActivationPolicyTests {
  @Test("inactive window click focuses pane while preserving AppKit activation")
  func inactiveWindowClickFocusesPaneWhilePreservingActivation() {
    #expect(
      PaneFocusActivationPolicy.mouseDownFocusAction(
        isAppActive: false,
        isWindowKey: false,
        isAlreadyFirstResponder: false
      ) == .focusAndPassThrough
    )
  }

  @Test("active window pane switch click focuses pane without forwarding terminal click")
  func activeWindowPaneSwitchClickFocusesPaneWithoutForwardingTerminalClick() {
    #expect(
      PaneFocusActivationPolicy.mouseDownFocusAction(
        isAppActive: true,
        isWindowKey: true,
        isAlreadyFirstResponder: false
      ) == .focusAndConsume
    )
  }

  @Test("already focused pane mouse down passes through")
  func alreadyFocusedPaneMouseDownPassesThrough() {
    #expect(
      PaneFocusActivationPolicy.mouseDownFocusAction(
        isAppActive: true,
        isWindowKey: true,
        isAlreadyFirstResponder: true
      ) == .passThrough
    )
  }

  @Test("chrome mouse down does not focus pane under title bar")
  func chromeMouseDownDoesNotFocusPaneUnderTitleBar() {
    #expect(
      PaneFocusActivationPolicy.mouseDownFocusAction(
        isAppActive: true,
        isWindowKey: true,
        isAlreadyFirstResponder: false,
        isClickInsideSurface: false
      ) == .passThrough
    )
  }

  @Test("only the selected pane remains terminal-active after pane switch")
  func onlySelectedPaneRemainsTerminalActiveAfterPaneSwitch() {
    let first = focusPaneID(1)
    let second = focusPaneID(2)
    let third = focusPaneID(3)

    #expect(
      PaneFocusActivationPolicy.selectedTerminalFocusStates(
        paneIds: [first, second, third],
        selectedPaneId: second
      ) == [
        first: false,
        second: true,
        third: false,
      ]
    )
  }

  @Test("window activation gates terminal focus states")
  func windowActivationGatesTerminalFocusStates() {
    let first = focusPaneID(1)
    let second = focusPaneID(2)

    #expect(
      PaneFocusActivationPolicy.windowTerminalFocusStates(
        paneIds: [first, second],
        selectedPaneId: second,
        isWindowKey: true
      ) == [
        first: false,
        second: true,
      ])
    #expect(
      PaneFocusActivationPolicy.windowTerminalFocusStates(
        paneIds: [first, second],
        selectedPaneId: second,
        isWindowKey: false
      ) == [
        first: false,
        second: false,
      ])
  }

  @Test("only the selected restored pane starts terminal-active")
  func onlySelectedRestoredPaneStartsTerminalActive() {
    let first = focusPaneID(1)
    let second = focusPaneID(2)
    let third = focusPaneID(3)

    #expect(
      PaneFocusActivationPolicy.initialTerminalFocusStates(
        paneIds: [first, second, third],
        selectedPaneId: second
      ) == [
        first: false,
        second: true,
        third: false,
      ]
    )
  }
}

private func focusPaneID(_ value: UInt8) -> UUID {
  UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
}
