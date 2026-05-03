import Foundation

public enum TerminalScreenEvent: Equatable, Sendable {
  case bell
  case progressChanged(Int?)
  case commandFinished(exitCode: Int16?)
  case childExited(exitCode: UInt32)
  case rendererHealthChanged(healthy: Bool)
}

public enum TerminalScreenIndicator: Equatable, Sendable {
  case bell(count: Int)
  case progress(percent: Int)
  case commandFinished(exitCode: Int16?)
  case childExited(exitCode: UInt32)
  case rendererUnhealthy
}

public struct TerminalScreenStatus: Equatable, Sendable {
  public var bellCount: Int
  public var progressPercent: Int?
  public var lastCommandExitCode: Int16?
  public var childExitCode: UInt32?
  public var rendererIsHealthy: Bool

  public init(
    bellCount: Int = 0,
    progressPercent: Int? = nil,
    lastCommandExitCode: Int16? = nil,
    childExitCode: UInt32? = nil,
    rendererIsHealthy: Bool = true
  ) {
    self.bellCount = bellCount
    self.progressPercent = progressPercent
    self.lastCommandExitCode = lastCommandExitCode
    self.childExitCode = childExitCode
    self.rendererIsHealthy = rendererIsHealthy
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

  public mutating func clearSuccessfulCommandFinished() {
    if lastCommandExitCode == 0 {
      lastCommandExitCode = nil
    }
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
    }
  }
}
