import Testing

@testable import SessionCore

@Suite("Terminal input policy")
struct TerminalInputPolicyTests {
  @Test("mouse button numbers map to terminal buttons")
  func mouseButtonNumbersMapToTerminalButtons() {
    #expect(TerminalInputPolicy.mouseButton(for: 0) == .left)
    #expect(TerminalInputPolicy.mouseButton(for: 1) == .right)
    #expect(TerminalInputPolicy.mouseButton(for: 2) == .middle)
    #expect(TerminalInputPolicy.mouseButton(for: 3) == .eight)
    #expect(TerminalInputPolicy.mouseButton(for: 4) == .nine)
    #expect(TerminalInputPolicy.mouseButton(for: 5) == .six)
    #expect(TerminalInputPolicy.mouseButton(for: 6) == .seven)
    #expect(TerminalInputPolicy.mouseButton(for: 7) == .four)
    #expect(TerminalInputPolicy.mouseButton(for: 8) == .five)
    #expect(TerminalInputPolicy.mouseButton(for: 9) == .ten)
    #expect(TerminalInputPolicy.mouseButton(for: 10) == .eleven)
    #expect(TerminalInputPolicy.mouseButton(for: 99) == .unknown)
  }

  @Test("precise scroll deltas are amplified")
  func preciseScrollDeltasAreAmplified() {
    #expect(TerminalInputPolicy.scrollDelta(deltaX: 1.5, deltaY: -2, hasPreciseDeltas: true) == (3, -4))
    #expect(TerminalInputPolicy.scrollDelta(deltaX: 1.5, deltaY: -2, hasPreciseDeltas: false) == (1.5, -2))
  }

  @Test("scroll modifier bits include precision and momentum")
  func scrollModifierBitsIncludePrecisionAndMomentum() {
    #expect(TerminalInputPolicy.scrollModifierBits(hasPreciseDeltas: false, momentum: .noMomentum) == 0)
    #expect(TerminalInputPolicy.scrollModifierBits(hasPreciseDeltas: true, momentum: .noMomentum) == 1)
    #expect(TerminalInputPolicy.scrollModifierBits(hasPreciseDeltas: false, momentum: .began) == 2)
    #expect(TerminalInputPolicy.scrollModifierBits(hasPreciseDeltas: true, momentum: .ended) == 9)
  }
}
