import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  init() {
    let view = SettingsView()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Settings"
    window.contentView = NSHostingView(rootView: view)
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }
}

private struct SettingsView: View {
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Settings")
        .font(.system(size: 22, weight: .semibold))

      SettingsSection(title: "Terminal") {
        SettingsRow(label: "Font", value: SmoovmuxConfig.terminalFontFamily)
        SettingsRow(label: "Config", value: SmoovmuxConfig.configURL.path)
      }

      HStack(spacing: 10) {
        Button("Open Config File") {
          openConfigFile()
        }
        Button("Reveal in Finder") {
          revealConfigFile()
        }
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.red)
      }

      Spacer()

      Text("Changes to terminal config apply to newly-created panes for now.")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func openConfigFile() {
    do {
      try ensureConfigFileExists()
      NSWorkspace.shared.open(SmoovmuxConfig.configURL)
      errorMessage = nil
    } catch {
      errorMessage = "Unable to open config: \(error.localizedDescription)"
    }
  }

  private func revealConfigFile() {
    do {
      try ensureConfigFileExists()
      NSWorkspace.shared.activateFileViewerSelecting([SmoovmuxConfig.configURL])
      errorMessage = nil
    } catch {
      errorMessage = "Unable to reveal config: \(error.localizedDescription)"
    }
  }

  private func ensureConfigFileExists() throws {
    try FileManager.default.createDirectory(
      at: SmoovmuxConfig.directoryURL,
      withIntermediateDirectories: true
    )
    if !FileManager.default.fileExists(atPath: SmoovmuxConfig.configURL.path) {
      try "".write(to: SmoovmuxConfig.configURL, atomically: true, encoding: .utf8)
    }
  }
}

private struct SettingsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title.uppercased())
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .tracking(0.7)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 8) {
        content
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }
  }
}

private struct SettingsRow: View {
  let label: String
  let value: String

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
      GridRow {
        Text(label)
          .foregroundStyle(.secondary)
          .frame(width: 58, alignment: .leading)
        Text(value)
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .textSelection(.enabled)
          .lineLimit(2)
      }
    }
    .font(.system(size: 13, weight: .medium))
  }
}
