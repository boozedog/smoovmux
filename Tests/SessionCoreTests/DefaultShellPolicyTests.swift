import Foundation
import Testing

@testable import SessionCore

@Suite("Default shell policy")
struct DefaultShellPolicyTests {
  @Test("system default option is first and includes resolved default")
  func systemDefaultOptionIsFirst() {
    let options = DefaultShellPolicy.options(
      availableShellPaths: ["/bin/bash", "/bin/zsh"],
      systemDefaultShellPath: "/bin/zsh"
    )

    #expect(options.map(\.id) == ["system", "/bin/bash", "/bin/zsh"])
    #expect(options.first?.title == "System default (/bin/zsh)")
  }

  @Test("available shell paths are trimmed deduplicated executable-looking absolute paths")
  func availableShellPathsAreNormalized() {
    let shells = DefaultShellPolicy.availableShells(
      shellsFileText: """
        # list of acceptable shells
        /bin/zsh
          /bin/bash
        /bin/zsh
        relative/sh
        /usr/local/bin/fish # comments are not valid inside shell paths

        """,
      isExecutableFile: { $0 != "/usr/local/bin/fish # comments are not valid inside shell paths" }
    )

    #expect(shells == ["/bin/zsh", "/bin/bash"])
  }

  @Test("stored system default launches nil command so ghostty uses its normal default")
  func systemDefaultLaunchCommandIsNil() {
    #expect(DefaultShellPolicy.launchCommand(forStoredShellPath: nil) == nil)
    #expect(DefaultShellPolicy.launchCommand(forStoredShellPath: "") == nil)
  }

  @Test("stored shell path launches that shell")
  func selectedShellLaunchesPath() {
    #expect(DefaultShellPolicy.launchCommand(forStoredShellPath: "/bin/bash") == "/bin/bash")
  }

  @Test("settings persist selected shell and remove system default")
  func settingsPersistSelectedShellAndRemoveSystemDefault() throws {
    let suiteName = "DefaultShellPolicyTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = DefaultShellSettings(defaults: defaults)

    settings.storedShellPath = "/bin/bash"
    #expect(settings.storedShellPath == "/bin/bash")
    #expect(settings.launchCommand == "/bin/bash")

    settings.storedShellPath = nil
    #expect(settings.storedShellPath == nil)
    #expect(settings.launchCommand == nil)
  }
}
