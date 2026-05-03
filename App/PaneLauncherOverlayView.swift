import AppKit
import PaneLauncher
import SwiftUI

struct PaneLauncherOverlay: View {
  @ObservedObject var tabManager: WorkspaceTabManager
  let presentation: PaneLauncherPresentation
  @State private var navigation = PaneLauncherNavigationState(rowCount: PaneLaunchChoice.builtins.count + 1)
  @State private var customText = ""
  @FocusState private var commandFieldFocused: Bool

  private var rowCount: Int { navigation.rowCount }

  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
        .ignoresSafeArea()
        .onTapGesture {
          launchShell()
        }

      VStack(alignment: .leading, spacing: 12) {
        Text("what to run?")
          .font(AppFonts.ui(size: 11))
          .tracking(0.9)
          .textCase(.uppercase)
          .foregroundStyle(.secondary)

        if navigation.mode == .list {
          launcherList
          Text("↑↓ select · ⏎ launch · esc shell · 1–\(rowCount) pick")
            .font(AppFonts.ui(size: 11))
            .italic()
            .foregroundStyle(.secondary)
        } else {
          TextField("command to run", text: $customText)
            .font(AppFonts.monospaced(size: 13))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay {
              RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor)
            }
            .focused($commandFieldFocused)
            .onSubmit(launchCustom)
            .onExitCommand {
              navigation.mode = .list
            }

          Text("⏎ run · esc back")
            .font(AppFonts.ui(size: 11))
            .italic()
            .foregroundStyle(.secondary)
        }
      }
      .padding(16)
      .frame(width: 340)
      .background(Color(nsColor: .textBackgroundColor))
      .foregroundStyle(Color(nsColor: .textColor))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color(nsColor: .separatorColor))
      }
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
      .onTapGesture {}
    }
    .background {
      if navigation.mode == .list {
        PaneLauncherKeyCaptureView { key in
          handle(key)
        }
      }
    }
    .onAppear {
      focusCurrentMode()
    }
    .onChange(of: navigation.mode) { _, _ in
      focusCurrentMode()
    }
  }

  private var launcherList: some View {
    VStack(spacing: 2) {
      ForEach(Array(PaneLaunchChoice.builtins.enumerated()), id: \.offset) { index, choice in
        launcherRow(index: index, title: choice.title) {
          launch(choice)
        }
      }
      launcherRow(index: PaneLaunchChoice.builtins.count, title: "enter a command…") {
        navigation.mode = .custom
      }
    }
  }

  private func launcherRow(index: Int, title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Text("\(index + 1)")
          .font(AppFonts.ui(size: 10, weight: .semibold))
          .frame(width: 18, height: 18)
          .background(navigation.selectedIndex == index ? Color.accentColor : Color(nsColor: .separatorColor))
          .foregroundStyle(navigation.selectedIndex == index ? Color(nsColor: .textBackgroundColor) : .secondary)
          .clipShape(RoundedRectangle(cornerRadius: 3))

        Text(title)
          .font(AppFonts.ui(size: 13))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
      .background(navigation.selectedIndex == index ? Color(nsColor: .controlBackgroundColor) : Color.clear)
      .overlay {
        RoundedRectangle(cornerRadius: 4)
          .stroke(navigation.selectedIndex == index ? Color.accentColor : Color.clear)
      }
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if hovering {
        navigation.selectedIndex = index
      }
    }
  }

  private func handle(_ key: PaneLauncherNavigationKey) {
    guard let intent = navigation.handle(key) else { return }
    perform(intent)
  }

  private func perform(_ intent: PaneLauncherNavigationIntent) {
    switch intent {
    case .pick(let index):
      if index == PaneLaunchChoice.builtins.count {
        navigation.mode = .custom
      } else {
        launch(PaneLaunchChoice.builtins[index])
      }
    case .launchShell:
      launchShell()
    case .launchCustom:
      launchCustom()
    }
  }

  private func launchShell() {
    launch(.shell)
  }

  private func launchCustom() {
    guard let request = PaneLaunchRequest(action: presentation.action, customCommandText: customText) else { return }
    tabManager.launch(request)
  }

  private func launch(_ choice: PaneLaunchChoice) {
    tabManager.launch(PaneLaunchRequest(action: presentation.action, choice: choice))
  }

  private func focusCurrentMode() {
    DispatchQueue.main.async {
      if navigation.mode == .custom {
        commandFieldFocused = true
      }
    }
  }
}

struct PaneLauncherKeyCaptureView: NSViewRepresentable {
  let onKey: (PaneLauncherNavigationKey) -> Void

  func makeNSView(context: Context) -> PaneLauncherKeyCaptureNSView {
    let view = PaneLauncherKeyCaptureNSView()
    view.onKey = onKey
    return view
  }

  func updateNSView(_ nsView: PaneLauncherKeyCaptureNSView, context: Context) {
    nsView.onKey = onKey
    DispatchQueue.main.async { [weak nsView] in
      guard let nsView else { return }
      nsView.window?.makeFirstResponder(nsView)
    }
  }
}

final class PaneLauncherKeyCaptureNSView: NSView {
  var onKey: ((PaneLauncherNavigationKey) -> Void)?

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
      !event.modifierFlags.contains(.option)
    else {
      super.keyDown(with: event)
      return
    }

    switch event.keyCode {
    case 36:
      onKey?(.enter)
    case 53:
      onKey?(.escape)
    case 125:
      onKey?(.down)
    case 126:
      onKey?(.up)
    default:
      if let characters = event.charactersIgnoringModifiers, let value = Int(characters) {
        onKey?(.number(value))
      }
    }
  }
}
