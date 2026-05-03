import Foundation
import Testing

@testable import SessionCore

@Suite("Terminal external action policy")
struct TerminalExternalActionPolicyTests {
  @Test("open URL accepts common external schemes")
  func openURLAcceptsCommonExternalSchemes() {
    #expect(
      TerminalExternalActionPolicy.openURL(from: "https://example.com")?.absoluteString == "https://example.com")
    #expect(TerminalExternalActionPolicy.openURL(from: "http://example.com")?.absoluteString == "http://example.com")
    #expect(
      TerminalExternalActionPolicy.openURL(from: "mailto:hello@example.com")?.absoluteString
        == "mailto:hello@example.com")
  }

  @Test("open URL rejects local or malformed values")
  func openURLRejectsLocalOrMalformedValues() {
    #expect(TerminalExternalActionPolicy.openURL(from: "") == nil)
    #expect(TerminalExternalActionPolicy.openURL(from: "not a url") == nil)
    #expect(TerminalExternalActionPolicy.openURL(from: "file:///Users/alice/secret") == nil)
    #expect(TerminalExternalActionPolicy.openURL(from: "javascript:alert(1)") == nil)
  }

  @Test("open URL trims whitespace")
  func openURLTrimsWhitespace() {
    #expect(
      TerminalExternalActionPolicy.openURL(from: "  https://example.com/path  ")?.absoluteString
        == "https://example.com/path")
  }

  @Test("c string payload uses explicit byte length")
  func cStringPayloadUsesExplicitLength() throws {
    let bytes = Array("https://example.com\0ignored".utf8)
    let value = bytes.withUnsafeBufferPointer { buffer in
      TerminalExternalActionPolicy.string(from: buffer.baseAddress, length: "https://example.com".utf8.count)
    }

    #expect(value == "https://example.com")
  }
}
