import AppKit
import PaneLauncher
import SwiftUI
import WorkspaceTabs

struct TabbedRootView: View {
  @ObservedObject var tabManager: WorkspaceTabManager

  var body: some View {
    ZStack {
      HStack(spacing: 0) {
        WorkspaceTabSidebar(tabManager: tabManager)
          .frame(width: 184)

        WorkspaceMainArea(tabManager: tabManager)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      if let presentation = tabManager.launcherPresentation {
        PaneLauncherOverlay(tabManager: tabManager, presentation: presentation)
          .id(presentation.id)
      }
    }
    .background(AppChromeColors.windowBackground)
    .ignoresSafeArea(.container, edges: .top)
  }
}

private enum AppChromeColors {
  static let windowBackground = Color(nsColor: NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1.0))
  static let sidebarBackground = Color(nsColor: NSColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0))
  static let mainBackground = Color(nsColor: NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1.0))
  static let chromeBorder = Color(nsColor: GhosttyConfigColors.dividerColor)
}

private struct WorkspaceMainArea: View {
  @ObservedObject var tabManager: WorkspaceTabManager

  var body: some View {
    VStack(spacing: 0) {
      WorkspaceTopBar(tabManager: tabManager)
        .frame(height: 34)
        .padding(.bottom, 6)

      TerminalSurfaceHost(pane: tabManager.selectedPane)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppChromeColors.mainBackground)
    }
    .background(AppChromeColors.mainBackground)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(AppChromeColors.chromeBorder)
        .frame(width: 1)
    }
  }
}

private struct WorkspaceTopBar: View {
  @ObservedObject var tabManager: WorkspaceTabManager

  var body: some View {
    HStack(spacing: 10) {
      Text(tabManager.selectedPaneTitle)
        .font(.system(size: 14, weight: .semibold, design: .monospaced))
        .lineLimit(1)
        .foregroundStyle(.primary)
        .padding(.leading, 22)

      Spacer()

      ChromeIconButton(systemName: "rectangle.split.2x1", help: "Split Right") {
        tabManager.showLauncher(action: .splitRight)
      }
      ChromeIconButton(systemName: "rectangle.split.1x2", help: "Split Down") {
        tabManager.showLauncher(action: .splitDown)
      }
      .padding(.trailing, 12)
    }
    .padding(.bottom, 8)
    .background(AppChromeColors.mainBackground)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(AppChromeColors.chromeBorder)
        .frame(height: 1)
    }
  }
}

private struct ChromeIconButton: View {
  let systemName: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 14, weight: .medium))
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .help(help)
  }
}

extension String {
  fileprivate var abbreviatedHomePath: String {
    let home = NSHomeDirectory()
    guard hasPrefix(home) else { return self }
    return "~" + dropFirst(home.count)
  }
}

private struct WorkspaceTabSidebar: View {
  @ObservedObject var tabManager: WorkspaceTabManager
  @State private var commandKeyDown = false
  @State private var flagsMonitor: Any?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Spacer()
        .frame(height: 28)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
            WorkspaceTabRow(
              tab: tab,
              shortcutIndex: index + 1,
              showShortcut: commandKeyDown,
              isSelected: tabManager.selectedTabId == tab.id,
              canClose: tabManager.tabs.count > 1,
              select: { tabManager.selectTab(tab.id) },
              close: { tabManager.closeTab(tab.id) }
            )
          }

          Button {
            tabManager.showLauncher(action: .newTab)
          } label: {
            HStack(spacing: 8) {
              Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
              Text("New Tab")
                .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(.primary)
          .help("New Tab")
          .accessibilityLabel("New Tab")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
      }
    }
    .background(AppChromeColors.sidebarBackground)
    .onAppear {
      flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
        commandKeyDown = event.modifierFlags.contains(.command)
        return event
      }
    }
    .onDisappear {
      if let flagsMonitor {
        NSEvent.removeMonitor(flagsMonitor)
      }
      flagsMonitor = nil
    }
  }
}

private struct WorkspaceTabRow: View {
  let tab: WorkspaceTabRecord
  let shortcutIndex: Int
  let showShortcut: Bool
  let isSelected: Bool
  let canClose: Bool
  let select: () -> Void
  let close: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: select) {
      HStack(spacing: 8) {
        Text(tab.title)
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)

        if showShortcut {
          Text("⌘\(shortcutIndex)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
        } else if hovering, canClose {
          Button(action: close) {
            Image(systemName: "xmark")
              .font(.system(size: 11, weight: .semibold))
              .frame(width: 16, height: 16)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .help("Close Tab")
          .accessibilityLabel("Close \(tab.title)")
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
    .onHover { hovering in
      self.hovering = hovering
    }
    .contextMenu {
      if canClose {
        Button("Close Tab", action: close)
      }
    }
  }
}

private struct PaneLauncherOverlay: View {
  @ObservedObject var tabManager: WorkspaceTabManager
  let presentation: PaneLauncherPresentation
  @State private var selected = 0
  @State private var mode = Mode.list
  @State private var customText = ""
  @FocusState private var commandFieldFocused: Bool

  private enum Mode {
    case list
    case custom
  }

  private var rowCount: Int {
    PaneLaunchChoice.builtins.count + 1
  }

  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
        .ignoresSafeArea()
        .onTapGesture {
          launchShell()
        }

      VStack(alignment: .leading, spacing: 12) {
        Text("what to run?")
          .font(.system(size: 11, weight: .regular))
          .tracking(0.9)
          .textCase(.uppercase)
          .foregroundStyle(.secondary)

        if mode == .list {
          launcherList
          Text("↑↓ select · ⏎ launch · esc shell · 1–\(rowCount) pick")
            .font(.system(size: 11))
            .italic()
            .foregroundStyle(.secondary)
        } else {
          TextField("command to run", text: $customText)
            .font(.system(size: 13, design: .monospaced))
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
              mode = .list
            }

          Text("⏎ run · esc back")
            .font(.system(size: 11))
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
      if mode == .list {
        PaneLauncherKeyCaptureView { key in
          handle(key)
        }
      }
    }
    .onAppear {
      focusCurrentMode()
    }
    .onChange(of: mode) { _, _ in
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
        mode = .custom
      }
    }
  }

  private func launcherRow(index: Int, title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Text("\(index + 1)")
          .font(.system(size: 10, weight: .semibold))
          .frame(width: 18, height: 18)
          .background(selected == index ? Color.accentColor : Color(nsColor: .separatorColor))
          .foregroundStyle(selected == index ? Color(nsColor: .textBackgroundColor) : .secondary)
          .clipShape(RoundedRectangle(cornerRadius: 3))

        Text(title)
          .font(.system(size: 13))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
      .background(selected == index ? Color(nsColor: .controlBackgroundColor) : Color.clear)
      .overlay {
        RoundedRectangle(cornerRadius: 4)
          .stroke(selected == index ? Color.accentColor : Color.clear)
      }
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if hovering {
        selected = index
      }
    }
  }

  private func handle(_ key: PaneLauncherKey) {
    switch (mode, key) {
    case (.list, .up):
      selected = (selected - 1 + rowCount) % rowCount
    case (.list, .down):
      selected = (selected + 1) % rowCount
    case (.list, .enter):
      pickSelected()
    case (.list, .escape):
      launchShell()
    case (.list, .number(let value)) where value >= 1 && value <= rowCount:
      selected = value - 1
      pickSelected()
    case (.custom, .escape):
      mode = .list
    case (.custom, .enter):
      launchCustom()
    default:
      break
    }
  }

  private func pickSelected() {
    if selected == PaneLaunchChoice.builtins.count {
      mode = .custom
      return
    }
    launch(PaneLaunchChoice.builtins[selected])
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
      if mode == .custom {
        commandFieldFocused = true
      }
    }
  }
}

private enum PaneLauncherKey {
  case up
  case down
  case enter
  case escape
  case number(Int)
}

private struct PaneLauncherKeyCaptureView: NSViewRepresentable {
  let onKey: (PaneLauncherKey) -> Void

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

private final class PaneLauncherKeyCaptureNSView: NSView {
  var onKey: ((PaneLauncherKey) -> Void)?

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

private struct TerminalSurfaceHost: NSViewRepresentable {
  let pane: PaneController?

  func makeNSView(context: Context) -> TerminalSurfaceContainerView {
    TerminalSurfaceContainerView()
  }

  func updateNSView(_ nsView: TerminalSurfaceContainerView, context: Context) {
    nsView.show(pane: pane)
  }
}

final class TerminalSurfaceContainerView: NSView {
  private weak var hostedSurfaceView: NSView?
  private var hostedConstraints: [NSLayoutConstraint] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }

  func show(pane: PaneController?) {
    guard let nextRootView = pane?.rootView else {
      clearHostedSurfaceView()
      return
    }

    if hostedSurfaceView === nextRootView {
      focus(nextRootView)
      return
    }

    clearHostedSurfaceView()
    hostedSurfaceView = nextRootView
    nextRootView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(nextRootView)
    hostedConstraints = [
      nextRootView.leadingAnchor.constraint(equalTo: leadingAnchor),
      nextRootView.trailingAnchor.constraint(equalTo: trailingAnchor),
      nextRootView.topAnchor.constraint(equalTo: topAnchor),
      nextRootView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ]
    NSLayoutConstraint.activate(hostedConstraints)
    focus(nextRootView)
  }

  private func clearHostedSurfaceView() {
    NSLayoutConstraint.deactivate(hostedConstraints)
    hostedConstraints = []
    hostedSurfaceView?.removeFromSuperview()
    hostedSurfaceView = nil
  }

  private func focus(_ rootView: NSView) {
    DispatchQueue.main.async { [weak rootView] in
      guard let rootView, let window = rootView.window else { return }
      guard let surfaceView = Self.firstSurface(in: rootView) else { return }
      window.makeFirstResponder(surfaceView)
    }
  }

  private static func firstSurface(in view: NSView) -> SmoovSurfaceView? {
    if let surfaceView = view as? SmoovSurfaceView {
      return surfaceView
    }
    for subview in view.subviews {
      if let surfaceView = firstSurface(in: subview) {
        return surfaceView
      }
    }
    return nil
  }
}
