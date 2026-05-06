import Foundation
import Testing

@testable import SessionCore

@Suite("Default working directory settings")
struct DefaultWorkingDirectorySettingsTests {
  @Test("default first-run directory is projects under home")
  func defaultFirstRunDirectoryIsProjectsUnderHome() throws {
    let home = URL(fileURLWithPath: "/Users/alice", isDirectory: true)
    let settings = AppSettings()

    #expect(DefaultWorkingDirectoryPolicy.storedPath(from: settings, homeDirectory: home) == "/Users/alice/projects")
  }

  @Test("configured directory persists in app settings store")
  func configuredDirectoryPersists() throws {
    let url = try temporarySettingsURL()
    let store = AppSettingsStore(settingsURL: url)

    try store.save(AppSettings(defaultWorkingDirectoryPath: "/tmp/project"))

    #expect(try store.load().defaultWorkingDirectoryPath == "/tmp/project")
  }

  @Test("invalid configured directory falls back to home")
  func invalidConfiguredDirectoryFallsBackToHome() throws {
    let home = try temporaryDirectory()
    let missing = home.appendingPathComponent("missing", isDirectory: true)

    let resolved = DefaultWorkingDirectoryPolicy.resolveTopLevelCwd(
      inheritedOrRestoredCwd: nil,
      storedPath: missing.path,
      homeDirectory: home,
      fileManager: .default
    )

    #expect(resolved == home)
  }

  @Test("inherited or restored cwd wins over default")
  func inheritedOrRestoredCwdWinsOverDefault() throws {
    let home = try temporaryDirectory()
    let restored = home.appendingPathComponent("restored", isDirectory: true)
    try FileManager.default.createDirectory(at: restored, withIntermediateDirectories: true)

    let resolved = DefaultWorkingDirectoryPolicy.resolveTopLevelCwd(
      inheritedOrRestoredCwd: restored,
      storedPath: home.path,
      homeDirectory: home,
      fileManager: .default
    )

    #expect(resolved == restored)
  }

  private func temporarySettingsURL() throws -> URL {
    try temporaryDirectory().appendingPathComponent("settings.json")
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("smoovmux-working-directory-tests")
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
