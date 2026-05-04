import AppKit
import SessionCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  init() {
    let view = SettingsView()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Settings"
    window.titlebarAppearsTransparent = true
    window.backgroundColor = .black
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
  @State private var summary = Self.makeSummary()
  @State private var shellOptions = Self.makeShellOptions()
  @State private var selectedShellID = Self.makeSelectedShellID()
  @State private var selectedLauncherID = Self.makeSelectedLauncherID()
  @State private var customLauncherCommand = Self.makeCustomLauncherCommand()

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Settings")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(.primary)
        Text("Terminal settings are Ghostty-compatible. Changes apply to newly-created panes for now.")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
      }

      SettingsSection(title: "Terminal") {
        ForEach(summary.terminalRows, id: \.label) { row in
          SettingsRow(label: row.label, value: row.value)
        }
      }

      SettingsSection(title: "Shell") {
        SettingsPickerRow(label: "Default shell", selection: $selectedShellID, options: shellOptions)
      }

      SettingsSection(title: "Launcher") {
        LauncherPickerRow(label: "Default", selection: $selectedLauncherID)
        if selectedLauncherID == "custom" {
          LauncherCommandRow(label: "Command", command: $customLauncherCommand)
        }
      }

      HStack(spacing: 10) {
        SettingsActionButton(title: "Open Config File", systemImage: "doc.text") {
          openConfigFile()
        }
        SettingsActionButton(title: "Reveal in Finder", systemImage: "folder") {
          revealConfigFile()
        }
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color(nsColor: .systemRed))
      }

      Spacer()
    }
    .padding(.top, 34)
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.black)
    .preferredColorScheme(.dark)
    .onAppear {
      refreshSummary()
      refreshShellOptions()
    }
    .onChange(of: selectedShellID) { _, newValue in
      saveSelectedShell(id: newValue)
    }
    .onChange(of: selectedLauncherID) { _, newValue in
      saveSelectedLauncher(id: newValue)
    }
    .onChange(of: customLauncherCommand) { _, _ in
      if selectedLauncherID == "custom" {
        saveSelectedLauncher(id: selectedLauncherID)
      }
    }
  }

  private func openConfigFile() {
    do {
      try ensureConfigFileExists()
      NSWorkspace.shared.open(SmoovmuxConfig.configURL)
      errorMessage = nil
      refreshSummary()
    } catch {
      errorMessage = "Unable to open config: \(error.localizedDescription)"
    }
  }

  private func revealConfigFile() {
    do {
      try ensureConfigFileExists()
      NSWorkspace.shared.activateFileViewerSelecting([SmoovmuxConfig.configURL])
      errorMessage = nil
      refreshSummary()
    } catch {
      errorMessage = "Unable to reveal config: \(error.localizedDescription)"
    }
  }

  private func refreshSummary() {
    summary = Self.makeSummary()
  }

  private func refreshShellOptions() {
    shellOptions = Self.makeShellOptions()
    selectedShellID = Self.makeSelectedShellID()
    selectedLauncherID = Self.makeSelectedLauncherID()
    customLauncherCommand = Self.makeCustomLauncherCommand()
  }

  private func saveSelectedShell(id: String) {
    let option = shellOptions.first { $0.id == id }
    DefaultShellSettings().storedShellPath = option?.shellPath
  }

  private func saveSelectedLauncher(id: String) {
    switch id {
    case "pi":
      DefaultLauncherSettings().choice = .pi
    case "codex":
      DefaultLauncherSettings().choice = .codex
    case "claude":
      DefaultLauncherSettings().choice = .claude
    case "custom":
      DefaultLauncherSettings().choice = .custom(command: customLauncherCommand)
    default:
      DefaultLauncherSettings().choice = .shell
    }
  }

  private static func makeSummary() -> SettingsConfigSummary {
    let configText = (try? String(contentsOf: SmoovmuxConfig.configURL, encoding: .utf8)) ?? ""
    return SettingsConfigSummary(
      configPath: SmoovmuxConfig.configURL.path,
      configText: configText,
      fallbackFontFamily: SmoovmuxConfig.terminalFontFamily
    )
  }

  private static func makeShellOptions() -> [DefaultShellOption] {
    DefaultShellPolicy.options(
      availableShellPaths: DefaultShellPolicy.readAvailableShells(),
      systemDefaultShellPath: DefaultShellPolicy.systemDefaultShellPath()
    )
  }

  private static func makeSelectedShellID() -> String {
    DefaultShellSettings().storedShellPath ?? DefaultShellPolicy.systemDefaultID
  }

  private static func makeSelectedLauncherID() -> String {
    DefaultLauncherSettings().choice.id
  }

  private static func makeCustomLauncherCommand() -> String {
    DefaultLauncherSettings().choice.customCommand ?? ""
  }

  private func ensureConfigFileExists() throws {
    try FileManager.default.createDirectory(
      at: SmoovmuxConfig.directoryURL,
      withIntermediateDirectories: true
    )
    if !FileManager.default.fileExists(atPath: SmoovmuxConfig.configURL.path) {
      try SmoovmuxConfig.defaultConfigText.write(to: SmoovmuxConfig.configURL, atomically: true, encoding: .utf8)
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
      VStack(alignment: .leading, spacing: 10) {
        content
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }
}

private struct SettingsRow: View {
  let label: String
  let value: String

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
      GridRow {
        Text(label)
          .foregroundStyle(.secondary)
          .frame(width: 84, alignment: .leading)
        Text(value)
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .foregroundStyle(.primary.opacity(0.92))
          .textSelection(.enabled)
          .lineLimit(2)
      }
    }
    .font(.system(size: 13, weight: .medium))
  }
}

private struct SettingsPickerRow: View {
  let label: String
  @Binding var selection: String
  let options: [DefaultShellOption]

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
      GridRow {
        Text(label)
          .foregroundStyle(.secondary)
          .frame(width: 84, alignment: .leading)
        Picker(label, selection: $selection) {
          ForEach(options) { option in
            Text(option.title).tag(option.id)
          }
        }
        .labelsHidden()
        .frame(maxWidth: 320, alignment: .leading)
      }
    }
    .font(.system(size: 13, weight: .medium))
  }
}

private struct LauncherPickerRow: View {
  let label: String
  @Binding var selection: String

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
      GridRow {
        Text(label)
          .foregroundStyle(.secondary)
          .frame(width: 84, alignment: .leading)
        Picker(label, selection: $selection) {
          ForEach(DefaultLauncherChoice.options, id: \.id) { option in
            Text(option.title).tag(option.id)
          }
        }
        .labelsHidden()
        .frame(maxWidth: 320, alignment: .leading)
      }
    }
    .font(.system(size: 13, weight: .medium))
  }
}

private struct LauncherCommandRow: View {
  let label: String
  @Binding var command: String

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
      GridRow {
        Text(label)
          .foregroundStyle(.secondary)
          .frame(width: 84, alignment: .leading)
        TextField("command to run", text: $command)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .frame(maxWidth: 320, alignment: .leading)
      }
    }
    .font(.system(size: 13, weight: .medium))
  }
}

private struct SettingsActionButton: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
