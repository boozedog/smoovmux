import Foundation

public struct TerminalNotification: Equatable, Sendable {
  public var title: String
  public var body: String

  public init(title: String, body: String) {
    self.title = title
    self.body = body
  }
}

public enum TerminalColorKind: Equatable, Sendable {
  case foreground
  case background
  case cursor
  case palette(Int)
}

public struct TerminalColorChange: Equatable, Sendable {
  public var kind: TerminalColorKind
  public var red: UInt8
  public var green: UInt8
  public var blue: UInt8

  public init(kind: TerminalColorKind, red: UInt8, green: UInt8, blue: UInt8) {
    self.kind = kind
    self.red = red
    self.green = green
    self.blue = blue
  }
}

public struct TerminalSearchState: Equatable, Sendable {
  public var needle: String?
  public var total: Int?
  public var selected: Int?

  public init(needle: String? = nil, total: Int? = nil, selected: Int? = nil) {
    self.needle = needle
    self.total = total
    self.selected = selected
  }
}

public struct TerminalScrollbar: Equatable, Sendable {
  public var total: UInt64
  public var offset: UInt64
  public var length: UInt64

  public init(total: UInt64, offset: UInt64, length: UInt64) {
    self.total = total
    self.offset = offset
    self.length = length
  }
}

public enum TerminalScreenEvent: Equatable, Sendable {
  case bell
  case progressChanged(Int?)
  case commandFinished(exitCode: Int16?)
  case childExited(exitCode: UInt32)
  case rendererHealthChanged(healthy: Bool)
  case desktopNotification(TerminalNotification)
  case mouseOverLink(String?)
  case colorChanged(TerminalColorChange)
  case configReloaded(soft: Bool)
  case configChanged
  case searchStarted(needle: String?)
  case searchEnded
  case searchTotal(Int?)
  case searchSelected(Int?)
  case scrollbarChanged(TerminalScrollbar)
  case visibleActivity(nowMilliseconds: Int64)
}

public enum TerminalScreenIndicator: Equatable, Sendable {
  case bell(count: Int)
  case progress(percent: Int)
  case commandFinished(exitCode: Int16?)
  case childExited(exitCode: UInt32)
  case rendererUnhealthy

  public var accessibilityLabel: String {
    switch self {
    case .bell(let count):
      return count == 1 ? "Terminal bell, 1 alert" : "Terminal bell, \(count) alerts"
    case .progress(let percent):
      return "Terminal progress \(percent) percent"
    case .commandFinished(let exitCode):
      if let exitCode, exitCode != 0 {
        return "Command failed with exit code \(exitCode)"
      }
      return "Command finished successfully"
    case .childExited(let exitCode):
      return "Child process exited with code \(exitCode)"
    case .rendererUnhealthy:
      return "Terminal renderer unhealthy"
    }
  }
}

public enum TerminalScreenAttentionPolicy {
  public static func shouldApply(_ event: TerminalScreenEvent, isSelectedScreen: Bool, appIsActive: Bool) -> Bool {
    if isSelectedScreen && appIsActive {
      return false
    }
    switch event {
    case .bell, .progressChanged, .commandFinished, .childExited, .rendererHealthChanged:
      return true
    case .desktopNotification, .mouseOverLink, .colorChanged, .configReloaded, .configChanged, .searchStarted,
      .searchEnded, .searchTotal, .searchSelected, .scrollbarChanged, .visibleActivity:
      return false
    }
  }
}

public struct TerminalLiveActivityPolicy: Equatable, Sendable {
  public var quietPeriodMilliseconds: Int64

  public init(quietPeriodMilliseconds: Int64 = 400) {
    self.quietPeriodMilliseconds = quietPeriodMilliseconds
  }

  public func isActive(lastActivityMilliseconds: Int64?, nowMilliseconds: Int64) -> Bool {
    guard let lastActivityMilliseconds, nowMilliseconds >= lastActivityMilliseconds else { return false }
    return nowMilliseconds - lastActivityMilliseconds < quietPeriodMilliseconds
  }

  public static func shouldShowActivity(isActive: Bool, isSelectedScreen: Bool, appIsActive: Bool) -> Bool {
    guard isActive else { return false }
    return !(isSelectedScreen && appIsActive)
  }
}

public enum TerminalScreenNotificationPolicy {
  public static func notification(for event: TerminalScreenEvent, screenTitle: String) -> TerminalNotification? {
    switch event {
    case .bell:
      return TerminalNotification(title: screenTitle, body: "Terminal bell")
    case .progressChanged(let percent):
      guard let percent else { return nil }
      return TerminalNotification(title: screenTitle, body: "Terminal progress \(max(0, min(100, percent))) percent")
    case .commandFinished(let exitCode):
      let body: String
      if let exitCode, exitCode != 0 {
        body = "Command failed with exit code \(exitCode)"
      } else {
        body = "Command finished successfully"
      }
      return TerminalNotification(title: screenTitle, body: body)
    case .childExited(let exitCode):
      return TerminalNotification(title: screenTitle, body: "Child process exited with code \(exitCode)")
    case .rendererHealthChanged(let healthy):
      guard !healthy else { return nil }
      return TerminalNotification(title: screenTitle, body: "Terminal renderer unhealthy")
    case .desktopNotification, .mouseOverLink, .colorChanged, .configReloaded, .configChanged, .searchStarted,
      .searchEnded, .searchTotal, .searchSelected, .scrollbarChanged, .visibleActivity:
      return nil
    }
  }
}

public struct TerminalScreenStatus: Equatable, Sendable {
  public var bellCount: Int
  public var progressPercent: Int?
  public var lastCommandExitCode: Int16?
  public var childExitCode: UInt32?
  public var rendererIsHealthy: Bool
  public var lastNotification: TerminalNotification?
  public var hoveredURL: String?
  public var lastColorChange: TerminalColorChange?
  public var lastConfigReloadWasSoft: Bool?
  public var configReloadCount: Int
  public var configChangeCount: Int
  public var search: TerminalSearchState?
  public var scrollbar: TerminalScrollbar?
  public var lastActivityMilliseconds: Int64?

  public init(
    bellCount: Int = 0,
    progressPercent: Int? = nil,
    lastCommandExitCode: Int16? = nil,
    childExitCode: UInt32? = nil,
    rendererIsHealthy: Bool = true,
    lastNotification: TerminalNotification? = nil,
    hoveredURL: String? = nil,
    lastColorChange: TerminalColorChange? = nil,
    lastConfigReloadWasSoft: Bool? = nil,
    configReloadCount: Int = 0,
    configChangeCount: Int = 0,
    search: TerminalSearchState? = nil,
    scrollbar: TerminalScrollbar? = nil,
    lastActivityMilliseconds: Int64? = nil
  ) {
    self.bellCount = bellCount
    self.progressPercent = progressPercent
    self.lastCommandExitCode = lastCommandExitCode
    self.childExitCode = childExitCode
    self.rendererIsHealthy = rendererIsHealthy
    self.lastNotification = lastNotification
    self.hoveredURL = hoveredURL
    self.lastColorChange = lastColorChange
    self.lastConfigReloadWasSoft = lastConfigReloadWasSoft
    self.configReloadCount = configReloadCount
    self.configChangeCount = configChangeCount
    self.search = search
    self.scrollbar = scrollbar
    self.lastActivityMilliseconds = lastActivityMilliseconds
  }

  public var indicator: TerminalScreenIndicator? {
    if !rendererIsHealthy {
      return .rendererUnhealthy
    }
    if let childExitCode {
      return .childExited(exitCode: childExitCode)
    }
    if let progressPercent {
      return .progress(percent: progressPercent)
    }
    if bellCount > 0 {
      return .bell(count: bellCount)
    }
    if lastCommandExitCode != nil {
      return .commandFinished(exitCode: lastCommandExitCode)
    }
    return nil
  }

  public mutating func clearBellAttention() {
    bellCount = 0
  }

  public mutating func acknowledgeSelection() {
    bellCount = 0
    lastCommandExitCode = nil
    childExitCode = nil
  }

  public mutating func apply(_ event: TerminalScreenEvent) {
    switch event {
    case .bell:
      bellCount += 1
    case .progressChanged(let percent):
      progressPercent = percent.map { max(0, min(100, $0)) }
    case .commandFinished(let exitCode):
      lastCommandExitCode = exitCode
    case .childExited(let exitCode):
      childExitCode = exitCode
    case .rendererHealthChanged(let healthy):
      rendererIsHealthy = healthy
    case .desktopNotification(let notification):
      lastNotification = notification
    case .mouseOverLink(let url):
      hoveredURL = url
    case .colorChanged(let colorChange):
      lastColorChange = colorChange
    case .configReloaded(let soft):
      lastConfigReloadWasSoft = soft
      configReloadCount += 1
    case .configChanged:
      configChangeCount += 1
    case .searchStarted(let needle):
      search = TerminalSearchState(needle: needle)
    case .searchEnded:
      search = nil
    case .searchTotal(let total):
      var nextSearch = search ?? TerminalSearchState()
      nextSearch.total = total
      search = nextSearch
    case .searchSelected(let selected):
      var nextSearch = search ?? TerminalSearchState()
      nextSearch.selected = selected
      search = nextSearch
    case .scrollbarChanged(let scrollbar):
      self.scrollbar = scrollbar
    case .visibleActivity(let nowMilliseconds):
      lastActivityMilliseconds = nowMilliseconds
    }
  }
}
