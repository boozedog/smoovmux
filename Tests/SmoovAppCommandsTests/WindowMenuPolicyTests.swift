import Foundation
import Testing

@testable import SmoovAppCommands

@Suite("main menu policy")
struct MainMenuPolicyTests {
  @Test("Screens appears left of Window in the menu bar")
  func screensPrecedesWindow() {
    #expect(MainMenuPolicy.titles == ["smoovmux", "File", "View", "Edit", "Screens", "Window"])
  }
}

@Suite("Window menu policy")
struct WindowMenuPolicyTests {
  @Test("base Window menu uses native window commands before workspace commands")
  func baseWindowMenuOrder() {
    #expect(
      WindowMenuPolicy.items(for: []) == [
        .command(.minimize),
        .command(.zoom),
        .separator,
        .command(.zoomPane),
        .separator,
        .command(.bringAllToFront),
      ])
  }

  @Test("dynamic window list appears at bottom in supplied order")
  func dynamicWindowListOrder() {
    let first = UUID()
    let second = UUID()

    let items = WindowMenuPolicy.items(for: [
      WindowMenuWindow(id: first, title: "Alpha", isKey: false),
      WindowMenuWindow(id: second, title: "Beta", isKey: true),
    ])

    #expect(
      items.suffix(3) == [
        .separator,
        .window(WindowMenuWindowItem(id: first, title: "Alpha", isChecked: false)),
        .window(WindowMenuWindowItem(id: second, title: "Beta", isChecked: true)),
      ])
  }

  @Test("blank window titles fall back to untitled")
  func blankWindowTitles() {
    let id = UUID()

    let items = WindowMenuPolicy.items(for: [WindowMenuWindow(id: id, title: "  ", isKey: true)])

    #expect(items.last == .window(WindowMenuWindowItem(id: id, title: "Untitled Window", isChecked: true)))
  }

  @Test("window and app command shortcuts do not collide")
  func windowCommandShortcutsDoNotCollide() {
    let shortcuts =
      AppCommand.allCases.compactMap(\.shortcut)
      + WindowMenuCommand.allCases.compactMap(\.shortcut)

    #expect(Set(shortcuts).count == shortcuts.count)
  }
}

@Suite("Screens menu policy")
struct ScreensMenuPolicyTests {
  @Test("screens menu uses tab-backed screen commands before the dynamic screen list")
  func screensMenuOrder() {
    #expect(
      ScreensMenuPolicy.items(for: []) == [
        .command(.newTab),
        .command(.closeTab),
        .separator,
        .command(.nextTab),
        .command(.previousTab),
      ])
  }

  @Test("dynamic screen list appears at bottom with selected screen checked")
  func dynamicScreenListOrder() {
    let first = UUID()
    let second = UUID()

    let items = ScreensMenuPolicy.items(for: [
      ScreensMenuScreen(id: first, title: "dotfiles", isSelected: false, index: 1),
      ScreensMenuScreen(id: second, title: "nix-darwin", isSelected: true, index: 2),
    ])

    #expect(
      items.suffix(3) == [
        .separator,
        .screen(
          ScreensMenuScreenItem(
            id: first,
            title: "1  dotfiles",
            isChecked: false,
            shortcut: KeyboardShortcutSpec(key: "1", modifiers: [.command])
          )),
        .screen(
          ScreensMenuScreenItem(
            id: second,
            title: "2  nix-darwin",
            isChecked: true,
            shortcut: KeyboardShortcutSpec(key: "2", modifiers: [.command])
          )),
      ])
  }

  @Test("blank screen titles fall back to untitled")
  func blankScreenTitles() {
    let id = UUID()

    let items = ScreensMenuPolicy.items(for: [ScreensMenuScreen(id: id, title: "  ", isSelected: true, index: 1)])

    #expect(
      items.last
        == .screen(
          ScreensMenuScreenItem(
            id: id,
            title: "1  Untitled Screen",
            isChecked: true,
            shortcut: KeyboardShortcutSpec(key: "1", modifiers: [.command])
          )))
  }
}
