import Foundation
import SessionCore
import Testing

@Suite("Default launcher settings")
struct DefaultLauncherSettingsTests {
  @Test("new settings default to shell launcher")
  func newSettingsDefaultToShellLauncher() throws {
    let store = AppSettingsStore(settingsURL: try temporarySettingsURL())

    #expect(DefaultLauncherSettings(store: store).choice == .shell)
  }

  @Test("launcher options match settings order")
  func launcherOptionsMatchSettingsOrder() {
    #expect(DefaultLauncherChoice.options == [.shell, .pi, .codex, .claude, .custom(command: "")])
    #expect(DefaultLauncherChoice.options.map(\.title) == ["Shell", "pi", "codex", "claude", "Enter a command…"])
  }

  @Test("persists builtin launcher choice")
  func persistsBuiltinLauncherChoice() throws {
    let store = AppSettingsStore(settingsURL: try temporarySettingsURL())
    let settings = DefaultLauncherSettings(store: store)

    settings.choice = .codex

    #expect(DefaultLauncherSettings(store: store).choice == .codex)
    #expect(try store.load().defaultLauncherKind == "codex")
  }

  @Test("persists trimmed custom command")
  func persistsTrimmedCustomCommand() throws {
    let store = AppSettingsStore(settingsURL: try temporarySettingsURL())
    let settings = DefaultLauncherSettings(store: store)

    settings.choice = .custom(command: " claude --resume ")

    #expect(DefaultLauncherSettings(store: store).choice == .custom(command: "claude --resume"))
  }

  @Test("blank custom command falls back to shell")
  func blankCustomCommandFallsBackToShell() throws {
    let store = AppSettingsStore(settingsURL: try temporarySettingsURL())
    try store.save(AppSettings(defaultLauncherKind: "custom", defaultLauncherCustomCommand: "  "))

    #expect(DefaultLauncherSettings(store: store).choice == .shell)
  }

  private func temporarySettingsURL() throws -> URL {
    let directory = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: FileManager.default.temporaryDirectory,
      create: true
    )
    return directory.appendingPathComponent("settings.json")
  }
}
