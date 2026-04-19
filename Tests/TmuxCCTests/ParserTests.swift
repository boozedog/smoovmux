import Foundation
import Testing

@testable import TmuxCC

@Suite("tmux -CC Parser")
struct ParserTests {
  private func feed(_ parser: Parser, _ string: String) -> [Token] {
    parser.push(Array(string.utf8))
  }

  // MARK: - Begin/end/error blocks (ported from ghostty control.zig tests)

  @Test func beginEndEmpty() {
    let parser = Parser()
    let tokens = feed(parser, "%begin 1578922740 269 1\n%end 1578922740 269 1\n")
    #expect(tokens == [.blockEnd(data: Data())])
  }

  @Test func beginErrorEmpty() {
    let parser = Parser()
    let tokens = feed(parser, "%begin 1578922740 269 1\n%error 1578922740 269 1\n")
    #expect(tokens == [.blockError(data: Data())])
  }

  @Test func beginEndData() {
    let parser = Parser()
    let tokens = feed(parser, "%begin 1578922740 269 1\nhello\nworld\n%end 1578922740 269 1\n")
    #expect(tokens == [.blockEnd(data: Data("hello\nworld".utf8))])
  }

  @Test func blockPayloadMayStartWithEnd() {
    let parser = Parser()
    let tokens = feed(parser, "%begin 1 1 1\n%end not really\nhello\n%end 1 1 1\n")
    #expect(tokens == [.blockEnd(data: Data("%end not really\nhello".utf8))])
  }

  @Test func blockPayloadMayStartWithError() {
    let parser = Parser()
    let tokens = feed(parser, "%begin 1 1 1\n%error not really\nhello\n%end 1 1 1\n")
    #expect(tokens == [.blockEnd(data: Data("%error not really\nhello".utf8))])
  }

  @Test func blockMayTerminateWithRealErrorAfterMisleadingPayload() {
    let parser = Parser()
    let tokens = feed(parser, "%begin 1 1 1\n%error not really\nhello\n%error 1 1 1\n")
    #expect(tokens == [.blockError(data: Data("%error not really\nhello".utf8))])
  }

  @Test func blockTerminatorRequiresExactTokenCount() {
    let parser = Parser()
    let tokens = feed(parser, "%begin 1 1 1\n%end 1 1 1 trailing\nhello\n%end 1 1 1\n")
    #expect(tokens == [.blockEnd(data: Data("%end 1 1 1 trailing\nhello".utf8))])
  }

  @Test func blockTerminatorRequiresNumericMetadata() {
    let parser = Parser()
    let tokens = feed(parser, "%begin 1 1 1\n%end foo bar baz\nhello\n%end 1 1 1\n")
    #expect(tokens == [.blockEnd(data: Data("%end foo bar baz\nhello".utf8))])
  }

  // MARK: - %output

  @Test func output() {
    let parser = Parser()
    let tokens = feed(parser, "%output %42 foo bar baz\n")
    #expect(tokens == [.output(paneId: 42, data: Data("foo bar baz".utf8))])
  }

  @Test func outputDecodesOctalEscapes() {
    let parser = Parser()
    let tokens = feed(parser, "%output %42 \\033ktitle\\033\\134\n")
    let expected: [UInt8] = [0x1b, 0x6b, 0x74, 0x69, 0x74, 0x6c, 0x65, 0x1b, 0x5c]
    #expect(tokens == [.output(paneId: 42, data: Data(expected))])
  }

  @Test func outputPreservesInvalidUtf8() {
    let parser = Parser()
    let raw: [UInt8] = Array("%output %7 ".utf8) + [0xff, 0xfe] + Array("\n".utf8)
    let tokens = parser.push(raw)
    #expect(tokens == [.output(paneId: 7, data: Data([0xff, 0xfe]))])
  }

  // MARK: - %session-*

  @Test func sessionChanged() {
    let parser = Parser()
    let tokens = feed(parser, "%session-changed $42 foo\n")
    #expect(tokens == [.sessionChanged(id: 42, name: "foo")])
  }

  @Test func sessionRenamed() {
    let parser = Parser()
    let tokens = feed(parser, "%session-renamed new-name\n")
    #expect(tokens == [.sessionRenamed(name: "new-name")])
  }

  @Test func sessionsChanged() {
    let parser = Parser()
    let tokens = feed(parser, "%sessions-changed\n")
    #expect(tokens == [.sessionsChanged])
  }

  @Test func sessionsChangedCarriageReturn() {
    let parser = Parser()
    let tokens = feed(parser, "%sessions-changed\r\n")
    #expect(tokens == [.sessionsChanged])
  }

  // MARK: - %exit

  @Test func exit() {
    let parser = Parser()
    let tokens = feed(parser, "%exit\n")
    #expect(tokens == [.exit])
  }

  @Test func exitPutsParserInBrokenState() {
    let parser = Parser()
    _ = feed(parser, "%exit\n")
    let trailing = feed(parser, "%output %1 hello\n")
    #expect(trailing.isEmpty)
  }

  // MARK: - Unknown fallthrough (M2+ notifications)

  @Test func layoutChangeFallsThroughToUnknown() {
    let parser = Parser()
    let line =
      "%layout-change @2 1234x791,0,0{617x791,0,0,0,617x791,618,0,1} 1234x791,0,0{617x791,0,0,0,617x791,618,0,1} *-"
    let tokens = feed(parser, line + "\n")
    #expect(tokens == [.unknown(line: line)])
  }

  @Test func windowAddFallsThroughToUnknown() {
    let parser = Parser()
    let tokens = feed(parser, "%window-add @14\n")
    #expect(tokens == [.unknown(line: "%window-add @14")])
  }

  // MARK: - Stream handling

  @Test func multipleNotificationsInOneChunk() {
    let parser = Parser()
    let tokens = feed(parser, "%sessions-changed\n%output %1 hi\n%exit\n")
    #expect(
      tokens == [
        .sessionsChanged,
        .output(paneId: 1, data: Data("hi".utf8)),
        .exit,
      ]
    )
  }

  @Test func bufferOverflowEmitsExit() {
    let parser = Parser(maxBufferBytes: 16)
    var tokens = parser.push(Array("%output %1 ".utf8))
    #expect(tokens.isEmpty)
    tokens = parser.push(Array(repeating: UInt8(0x61), count: 32))
    #expect(tokens == [.exit])
  }
}
