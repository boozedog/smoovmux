public enum TerminalMouseButton: Equatable, Sendable {
  case left
  case right
  case middle
  case four
  case five
  case six
  case seven
  case eight
  case nine
  case ten
  case eleven
  case unknown
}

public enum TerminalMouseMomentum: Int32, Equatable, Sendable {
  case noMomentum = 0
  case began = 1
  case stationary = 2
  case changed = 3
  case ended = 4
  case cancelled = 5
  case mayBegin = 6
}

public enum TerminalInputPolicy {
  public static func mouseButton(for buttonNumber: Int) -> TerminalMouseButton {
    switch buttonNumber {
    case 0:
      return .left
    case 1:
      return .right
    case 2:
      return .middle
    case 3:
      return .eight
    case 4:
      return .nine
    case 5:
      return .six
    case 6:
      return .seven
    case 7:
      return .four
    case 8:
      return .five
    case 9:
      return .ten
    case 10:
      return .eleven
    default:
      return .unknown
    }
  }

  public static func scrollDelta(deltaX: Double, deltaY: Double, hasPreciseDeltas: Bool) -> (x: Double, y: Double) {
    guard hasPreciseDeltas else { return (deltaX, deltaY) }
    return (deltaX * 2, deltaY * 2)
  }

  public static func scrollModifierBits(hasPreciseDeltas: Bool, momentum: TerminalMouseMomentum) -> Int32 {
    var value: Int32 = hasPreciseDeltas ? 1 : 0
    value |= momentum.rawValue << 1
    return value
  }
}
