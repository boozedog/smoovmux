import AppKit
import SwiftUI

struct TerminalSurfaceHost: NSViewRepresentable {
  let pane: PaneController?

  func makeNSView(context: Context) -> TerminalSurfaceContainerView {
    TerminalSurfaceContainerView()
  }

  func updateNSView(_ nsView: TerminalSurfaceContainerView, context: Context) {
    nsView.show(rootView: pane?.rootView, focusOnAttach: true)
  }
}

struct CommandSurfaceHost: NSViewRepresentable {
  let pane: CommandPaneController

  func makeNSView(context: Context) -> TerminalSurfaceContainerView {
    TerminalSurfaceContainerView()
  }

  func updateNSView(_ nsView: TerminalSurfaceContainerView, context: Context) {
    nsView.show(rootView: pane.rootView, focusOnAttach: false)
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

  func show(rootView: NSView?, focusOnAttach: Bool) {
    guard let nextRootView = rootView else {
      clearHostedSurfaceView()
      return
    }

    if hostedSurfaceView === nextRootView {
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
    if focusOnAttach {
      focus(nextRootView)
    }
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
