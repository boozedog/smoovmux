import Foundation
import Testing

@testable import TmuxCC

@Suite("tmux %output octal decoder")
struct OctalDecodeTests {
  @Test func basicOctalDecode() {
    let input = Data("\\033[?2004h".utf8)
    let expected: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x30, 0x34, 0x68]
    #expect(decodeTmuxOutput(input) == Data(expected))
  }

  @Test func malformedEscapeEmitsQuestionMark() {
    // Matches ghostty: partial octal digits are consumed into the malformed
    // run, so "\0x3" decodes to "?x3" (not "?0x3").
    let input = Data("\\0x3".utf8)
    let expected: [UInt8] = [0x3f, 0x78, 0x33]
    #expect(decodeTmuxOutput(input) == Data(expected))
  }

  @Test func backslashEncodedAsOctal() {
    let input = Data("a\\134b".utf8)
    #expect(decodeTmuxOutput(input) == Data("a\\b".utf8))
  }

  @Test func emptyInput() {
    #expect(decodeTmuxOutput(Data()) == Data())
  }

  @Test func noEscapesPassthrough() {
    let input = Data("hello world".utf8)
    #expect(decodeTmuxOutput(input) == input)
  }
}
