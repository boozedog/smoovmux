import Testing

@testable import WorkspaceSidebar

@Suite("Screen row accessory policy")
struct ScreenRowAccessoryPolicyTests {
  @Test("closable rows show close button on hover")
  func closableRowsShowCloseButtonOnHover() {
    #expect(
      ScreenRowAccessoryPolicy.accessory(
        canClose: true,
        isHovering: true,
        showShortcut: false,
        hasIndicator: true
      ) == .closeButton)
  }

  @Test("closable rows keep indicator when not hovered")
  func closableRowsKeepIndicatorWhenNotHovered() {
    #expect(
      ScreenRowAccessoryPolicy.accessory(
        canClose: true,
        isHovering: false,
        showShortcut: false,
        hasIndicator: true
      ) == .indicator)
  }

  @Test("keyboard shortcut takes precedence while command key is down")
  func shortcutTakesPrecedence() {
    #expect(
      ScreenRowAccessoryPolicy.accessory(
        canClose: true,
        isHovering: false,
        showShortcut: true,
        hasIndicator: true
      ) == .shortcut)
  }

  @Test("non-closable rows can show indicators")
  func nonClosableRowsCanShowIndicators() {
    #expect(
      ScreenRowAccessoryPolicy.accessory(
        canClose: false,
        isHovering: false,
        showShortcut: false,
        hasIndicator: true
      ) == .indicator)
  }
}
