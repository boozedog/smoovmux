import Testing

@testable import PushToTalkDictation

struct DictationTextSanitizerTests {
  @Test func trimsLeadingAndTrailingWhitespace() {
    let sanitizer = DictationTextSanitizer()

    #expect(sanitizer.sanitizeForPTYInsert("  explain this error  ") == "explain this error")
  }

  @Test func convertsNewlinesToSpaces() {
    let sanitizer = DictationTextSanitizer()

    #expect(
      sanitizer.sanitizeForPTYInsert("first line\nsecond line\r\nthird line\rfourth line")
        == "first line second line third line fourth line")
  }

  @Test func collapsesRepeatedWhitespace() {
    let sanitizer = DictationTextSanitizer()

    #expect(sanitizer.sanitizeForPTYInsert("please   explain\tthis") == "please explain this")
  }

  @Test func rejectsWhitespaceOnlyTranscript() {
    let sanitizer = DictationTextSanitizer()

    #expect(sanitizer.sanitizeForPTYInsert(" \n\r\t ") == nil)
  }
}
