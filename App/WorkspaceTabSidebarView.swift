import AppKit
import SwiftUI
import WorkspaceSidebar
import WorkspaceTabs

struct WorkspaceTabSidebar: View {
  @ObservedObject var tabManager: WorkspaceTabManager
  @State private var commandKeyDown = false
  @State private var flagsMonitor: Any?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer()
        .frame(height: 54)

      HStack {
        Text("SCREENS")
          .font(AppFonts.monospaced(size: 11, weight: .semibold))
          .tracking(0.7)
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          tabManager.showLauncher(action: .newTab)
        } label: {
          Image(systemName: "plus")
            .font(AppFonts.ui(size: 13, weight: .semibold))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("New Screen")
        .accessibilityLabel("New Screen")
      }
      .padding(.horizontal, 10)
      .padding(.bottom, 8)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
            WorkspaceTabRow(
              tab: tab,
              shortcutIndex: index + 1,
              showShortcut: commandKeyDown,
              isSelected: tabManager.selectedTabId == tab.id,
              canClose: tabManager.tabs.count > 1,
              indicator: tabManager.terminalStatus(for: tab.id).indicator,
              select: { tabManager.selectTab(tab.id) },
              close: { tabManager.closeTab(tab.id) }
            )
          }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
      }

      Spacer(minLength: 0)

      Button {
        NSApp.sendAction(
          #selector(AppDelegate.showSettingsWindow(_:)),
          to: NSApp.delegate,
          from: nil
        )
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "gearshape")
            .font(AppFonts.ui(size: 12, weight: .medium))
          Text("Settings")
            .font(AppFonts.monospaced(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary.opacity(0.9))
      .help("Settings")
      .accessibilityLabel("Settings")
      .padding(.bottom, 10)
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

struct WorkspaceTabRow: View {
  let tab: WorkspaceTabRecord
  let shortcutIndex: Int
  let showShortcut: Bool
  let isSelected: Bool
  let canClose: Bool
  let indicator: TerminalScreenIndicator?
  let select: () -> Void
  let close: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: select) {
      HStack(spacing: 8) {
        Text("\(shortcutIndex)")
          .font(AppFonts.monospaced(size: 12, weight: .medium))
          .foregroundStyle(isSelected ? .primary : .secondary)
          .frame(width: 14, alignment: .leading)

        Text(tab.title)
          .font(AppFonts.monospaced(size: 13, weight: .semibold))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)

        if showShortcut {
          Text("⌘\(shortcutIndex)")
            .font(AppFonts.monospaced(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        } else if hovering, canClose {
          Button(action: close) {
            Image(systemName: "xmark")
              .font(AppFonts.ui(size: 11, weight: .semibold))
              .frame(width: 16, height: 16)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .help("Close Tab")
          .accessibilityLabel("Close \(tab.title)")
        } else if let indicator {
          TerminalScreenIndicatorView(indicator: indicator)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
      .background {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(isSelected ? Color.white.opacity(0.06) : Color.clear)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .stroke(isSelected ? Color(nsColor: .systemBlue).opacity(0.85) : Color.clear, lineWidth: 1)
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

struct TerminalScreenIndicatorView: View {
  let indicator: TerminalScreenIndicator

  var body: some View {
    switch indicator {
    case .bell(let count):
      HStack(spacing: 3) {
        Image(systemName: "bell.fill")
        if count > 1 {
          Text("\(count)")
            .font(AppFonts.monospaced(size: 10, weight: .semibold))
        }
      }
      .font(AppFonts.ui(size: 12, weight: .semibold))
      .foregroundStyle(Color(nsColor: .systemYellow))
    case .progress(let percent):
      Text("\(percent)%")
        .font(AppFonts.monospaced(size: 10, weight: .semibold))
        .foregroundStyle(Color(nsColor: .systemYellow))
    case .commandFinished(let exitCode):
      Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(exitCode == 0 ? .secondary : Color(nsColor: .systemRed))
    case .childExited:
      Image(systemName: "stop.circle.fill")
        .foregroundStyle(Color(nsColor: .systemOrange))
    case .rendererUnhealthy:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Color(nsColor: .systemRed))
    }
  }
}
