import Foundation

public enum MainMenuPolicy {
  public static let titles = ["smoovmux", "File", "View", "Edit", "Screens", "Window"]
}

public struct WindowMenuWindow: Equatable, Sendable {
  public let id: UUID
  public let title: String
  public let isKey: Bool

  public init(id: UUID, title: String, isKey: Bool) {
    self.id = id
    self.title = title
    self.isKey = isKey
  }
}

public struct WindowMenuWindowItem: Equatable, Sendable {
  public let id: UUID
  public let title: String
  public let isChecked: Bool

  public init(id: UUID, title: String, isChecked: Bool) {
    self.id = id
    self.title = title
    self.isChecked = isChecked
  }
}

public enum WindowMenuCommand: CaseIterable, Equatable, Sendable {
  case minimize
  case zoom
  case zoomPane
  case bringAllToFront

  public var title: String {
    switch self {
    case .minimize:
      return "Minimize"
    case .zoom:
      return "Zoom"
    case .zoomPane:
      return "Zoom Pane"
    case .bringAllToFront:
      return "Bring All to Front"
    }
  }

  public var shortcut: KeyboardShortcutSpec? {
    switch self {
    case .minimize:
      return KeyboardShortcutSpec(key: "m", modifiers: [.command])
    case .zoom, .zoomPane, .bringAllToFront:
      return nil
    }
  }
}

public enum WindowMenuItem: Equatable, Sendable {
  case command(WindowMenuCommand)
  case separator
  case window(WindowMenuWindowItem)
}

public enum WindowMenuPolicy {
  public static func items(for windows: [WindowMenuWindow]) -> [WindowMenuItem] {
    var items: [WindowMenuItem] = [
      .command(.minimize),
      .command(.zoom),
      .separator,
      .command(.zoomPane),
      .separator,
      .command(.bringAllToFront),
    ]

    if !windows.isEmpty {
      items.append(.separator)
      items.append(contentsOf: windows.map(windowItem(for:)))
    }

    return items
  }

  private static func windowItem(for window: WindowMenuWindow) -> WindowMenuItem {
    .window(
      WindowMenuWindowItem(
        id: window.id,
        title: normalizedTitle(window.title),
        isChecked: window.isKey
      )
    )
  }

  private static func normalizedTitle(_ title: String) -> String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? "Untitled Window" : title
  }
}

public struct ScreensMenuScreen: Equatable, Sendable {
  public let id: UUID
  public let title: String
  public let isSelected: Bool
  public let index: Int

  public init(id: UUID, title: String, isSelected: Bool, index: Int) {
    self.id = id
    self.title = title
    self.isSelected = isSelected
    self.index = index
  }
}

public struct ScreensMenuScreenItem: Equatable, Sendable {
  public let id: UUID
  public let title: String
  public let isChecked: Bool
  public let shortcut: KeyboardShortcutSpec?

  public init(id: UUID, title: String, isChecked: Bool, shortcut: KeyboardShortcutSpec?) {
    self.id = id
    self.title = title
    self.isChecked = isChecked
    self.shortcut = shortcut
  }
}

public enum ScreensMenuItem: Equatable, Sendable {
  case command(AppCommand)
  case separator
  case screen(ScreensMenuScreenItem)
}

public enum ScreensMenuPolicy {
  public static func items(for screens: [ScreensMenuScreen]) -> [ScreensMenuItem] {
    var items: [ScreensMenuItem] = [
      .command(.newTab),
      .command(.closeTab),
      .separator,
      .command(.nextTab),
      .command(.previousTab),
    ]

    if !screens.isEmpty {
      items.append(.separator)
      items.append(contentsOf: screens.map(screenItem(for:)))
    }

    return items
  }

  private static func screenItem(for screen: ScreensMenuScreen) -> ScreensMenuItem {
    .screen(
      ScreensMenuScreenItem(
        id: screen.id,
        title: "\(screen.index)  \(normalizedTitle(screen.title))",
        isChecked: screen.isSelected,
        shortcut: shortcut(for: screen.index)
      )
    )
  }

  private static func normalizedTitle(_ title: String) -> String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedTitle.isEmpty ? "Untitled Screen" : title
  }

  private static func shortcut(for index: Int) -> KeyboardShortcutSpec? {
    guard 1...9 ~= index else { return nil }
    return KeyboardShortcutSpec(key: "\(index)", modifiers: [.command])
  }
}
