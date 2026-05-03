import Foundation
import SessionCore
import Testing

@Suite("Git root resolver")
struct GitRootResolverTests {
  @Test("non-git directory returns nil")
  func nonGitDirectoryReturnsNil() async throws {
    let temp = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }

    let root = try await GitRootResolver().resolve(cwd: temp)

    #expect(root == nil)
  }

  @Test("nested directory resolves repository root")
  func nestedDirectoryResolvesRoot() async throws {
    let temp = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    try runGit(["init"], cwd: temp)
    let nested = temp.appendingPathComponent("a/b", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    let root = try await GitRootResolver().resolve(cwd: nested)

    #expect(root?.standardizedFileURL == temp.standardizedFileURL)
  }
}

private func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("smoovmux-git-root-tests")
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func runGit(_ arguments: [String], cwd: URL) throws {
  let process = Process()
  process.executableURL = try BinaryResolver.resolve("git")
  process.arguments = arguments
  process.currentDirectoryURL = cwd
  process.standardOutput = Pipe()
  process.standardError = Pipe()
  try process.run()
  process.waitUntilExit()
  #expect(process.terminationStatus == 0)
}
