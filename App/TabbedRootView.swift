import AppKit
import SwiftUI
import WorkspaceTabs

struct TabbedRootView: View {
  @ObservedObject var tabManager: WorkspaceTabManager

  var body: some View {
    HStack(spacing: 0) {
      WorkspaceTabSidebar(tabManager: tabManager)
        .frame(width: 180)

      Divider()

      TerminalSurfaceHost(pane: tabManager.selectedPane)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
  }
}

private struct WorkspaceTabSidebar: View {
  @ObservedObject var tabManager: WorkspaceTabManager

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text("Tabs")
          .font(.headline)
        Spacer()
        Button {
          tabManager.addTab()
        } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .help("New Tab")
        .accessibilityLabel("New Tab")
      }
      .padding(.top, 12)
      .padding(.horizontal, 12)

      ScrollView {
        LazyVStack(spacing: 4) {
          ForEach(tabManager.tabs) { tab in
            WorkspaceTabRow(
              tab: tab,
              isSelected: tabManager.selectedTabId == tab.id,
              canClose: tabManager.tabs.count > 1,
              select: { tabManager.selectTab(tab.id) },
              close: { tabManager.closeTab(tab.id) }
            )
          }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
      }
    }
    .background(.regularMaterial)
  }
}

private struct WorkspaceTabRow: View {
  let tab: WorkspaceTabRecord
  let isSelected: Bool
  let canClose: Bool
  let select: () -> Void
  let close: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 8) {
        Image(systemName: "terminal")
          .foregroundStyle(isSelected ? .primary : .secondary)
        Text(tab.title)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)

        if canClose {
          Button(action: close) {
            Image(systemName: "xmark")
              .font(.system(size: 10, weight: .semibold))
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .help("Close Tab")
          .accessibilityLabel("Close \(tab.title)")
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
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
