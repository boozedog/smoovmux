import Testing

@testable import SmoovLog

@Suite("Log redaction")
struct RedactTests {
  @Test("password-like fields are redacted")
  func passwordLikeFieldsAreRedacted() {
    #expect(redact("password=hunter2") == "password=<redacted>")
    #expect(redact("token=abc123") == "token=<redacted>")
    #expect(redact("secret=abc123") == "secret=<redacted>")
    #expect(redact("key=/Users/me/.ssh/id_ed25519") == "key=<redacted>")
  }

  @Test("redaction is case insensitive and preserves field spelling")
  func redactionIsCaseInsensitive() {
    #expect(redact("TOKEN=abc123") == "TOKEN=<redacted>")
    #expect(redact("ApiKey=value") == "ApiKey=<redacted>")
  }

  @Test("multiple sensitive fields are redacted in one message")
  func multipleFieldsAreRedacted() {
    #expect(redact("token=abc password=def ok=true") == "token=<redacted> password=<redacted> ok=true")
  }

  @Test("non-sensitive messages are unchanged")
  func nonSensitiveMessagesAreUnchanged() {
    #expect(redact("pane launched with default shell") == "pane launched with default shell")
  }
}
