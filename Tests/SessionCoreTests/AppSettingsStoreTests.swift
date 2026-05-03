import Foundation
import Testing

@testable import SessionCore

@Suite("App settings store")
struct AppSettingsStoreTests {
  @Test("missing settings file uses defaults without creating a file")
  func missingSettingsFileUsesDefaults() throws {
    let url = try temporarySettingsURL()
    let store = AppSettingsStore(settingsURL: url)

    #expect(try store.load().defaultShellPath == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("saves default shell path as JSON under config directory")
  func savesDefaultShellPath() throws {
    let url = try temporarySettingsURL()
    let store = AppSettingsStore(settingsURL: url)

    try store.save(AppSettings(defaultShellPath: "/bin/bash"))

    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("defaultShellPath"))
    #expect(try store.load().defaultShellPath == "/bin/bash")
  }

  @Test("removing default shell path persists system default selection")
  func removingDefaultShellPathPersistsSystemDefault() throws {
    let url = try temporarySettingsURL()
    let store = AppSettingsStore(settingsURL: url)

    var settings = AppSettings(defaultShellPath: "/bin/bash")
    try store.save(settings)
    settings.defaultShellPath = nil
    try store.save(settings)

    #expect(try store.load().defaultShellPath == nil)
    #expect(DefaultShellSettings(store: store).launchCommand == nil)
  }

  @Test("stored shell path wraps pane commands")
  func storedShellPathWrapsPaneCommands() throws {
    let url = try temporarySettingsURL()
    let store = AppSettingsStore(settingsURL: url)
    try store.save(AppSettings(defaultShellPath: "/bin/bash"))

    #expect(DefaultShellSettings(store: store).wrappedCommandLaunchCommand(for: "pi") == "'/bin/bash' -l -i -c 'pi'")
  }

  @Test("invalid settings file falls back to defaults")
  func invalidSettingsFileFallsBackToDefaults() throws {
    let url = try temporarySettingsURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "not json".write(to: url, atomically: true, encoding: .utf8)

    #expect(try AppSettingsStore(settingsURL: url).load().defaultShellPath == nil)
  }

  @Test("default settings URL is under dot config smoovmux")
  func defaultSettingsURLIsUnderDotConfig() {
    let path = AppSettingsStore.defaultSettingsURL.path

    #expect(path.hasSuffix("/.config/smoovmux/settings.json"))
  }

  private func temporarySettingsURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("smoovmux-settings-tests")
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("settings.json")
  }
}
