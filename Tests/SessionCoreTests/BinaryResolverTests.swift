import Darwin
import Foundation
import Testing

@testable import SessionCore

@Suite("BinaryResolver")
struct BinaryResolverTests {
  @Test func pathComponentsIncludeSystemDirs() {
    let dirs = BinaryResolver.pathComponents()
    #expect(dirs.contains("/usr/bin"))
    #expect(dirs.contains("/bin"))
  }

  @Test func pathComponentsAreDeduplicated() {
    let dirs = BinaryResolver.pathComponents()
    let unique = Set(dirs)
    #expect(dirs.count == unique.count)
  }

  @Test func resolveFindsSystemBinary() throws {
    let url = try BinaryResolver.resolve("true")
    // Could be /usr/bin/true, /bin/true, or a shimmed Nix path — only assert shape.
    #expect(url.isFileURL)
    #expect(url.lastPathComponent == "true")
    var st = stat()
    #expect(stat(url.path, &st) == 0)
    #expect(access(url.path, X_OK) == 0)
  }

  @Test func resolveThrowsNotFoundForMissingBinary() {
    #expect(throws: BinaryResolver.ResolveError.notFound(name: "smoovmux-does-not-exist-xyz")) {
      _ = try BinaryResolver.resolve("smoovmux-does-not-exist-xyz")
    }
  }

  @Test func overrideIsUsedWhenExecutable() throws {
    let override = "/bin/ls"
    let url = try BinaryResolver.resolve("ssh", override: override)
    #expect(url.path == override)
  }

  @Test func overrideThatIsMissingThrowsNotExecutable() {
    let bogus = "/tmp/smoovmux-bogus-\(UUID().uuidString)"
    #expect(throws: BinaryResolver.ResolveError.notExecutable(path: bogus)) {
      _ = try BinaryResolver.resolve("ssh", override: bogus)
    }
  }

  @Test func overrideThatPointsAtDirectoryThrowsNotExecutable() {
    let dir = "/tmp"
    #expect(throws: BinaryResolver.ResolveError.notExecutable(path: dir)) {
      _ = try BinaryResolver.resolve("ssh", override: dir)
    }
  }

  @Test func overrideThatIsNotExecutableThrowsNotExecutable() throws {
    // A regular file with mode 0644 should fail the X_OK check.
    let path = NSTemporaryDirectory() + "smoovmux-noexec-\(UUID().uuidString)"
    FileManager.default.createFile(atPath: path, contents: Data("x".utf8), attributes: [.posixPermissions: 0o644])
    defer { try? FileManager.default.removeItem(atPath: path) }

    #expect(throws: BinaryResolver.ResolveError.notExecutable(path: path)) {
      _ = try BinaryResolver.resolve("ssh", override: path)
    }
  }

  @Test func emptyOverrideIsTreatedAsUnset() throws {
    // An empty override must not short-circuit the PATH search.
    let url = try BinaryResolver.resolve("true", override: "")
    #expect(url.lastPathComponent == "true")
  }

  @Test func fallbackIsUsedWhenPathSearchFails() throws {
    let url = try BinaryResolver.resolve(
      "smoovmux-missing-\(UUID().uuidString)",
      fallback: "/bin/ls"
    )
    #expect(url.path == "/bin/ls")
  }

  @Test func overridePreemptsFallback() throws {
    let url = try BinaryResolver.resolve(
      "ssh",
      override: "/bin/ls",
      fallback: "/bin/cat"
    )
    #expect(url.path == "/bin/ls")
  }

  @Test func loginShellPathIsMemoized() {
    // Both reads should be identical (memoized by `static let`).
    let first = BinaryResolver.loginShellPATH
    let second = BinaryResolver.loginShellPATH
    #expect(first == second)
  }

  @Test func fallbackPathContainsExpectedDirectories() {
    let fallback = BinaryResolver.fallbackPATH
    #expect(fallback.contains("/opt/homebrew/bin"))
    #expect(fallback.contains("/usr/bin"))
    #expect(fallback.contains("/bin"))
  }
}
