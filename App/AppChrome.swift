import AppKit
import SwiftUI

enum AppChromeColors {
  static let windowBackground = Color.black
  static let sidebarBackground = Color.black
  static let mainBackground = Color.black
  static let chromeBorder = Color.clear
}

struct WindowDragArea: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowDragNSView {
    WindowDragNSView()
  }

  func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

final class WindowDragNSView: NSView {
  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}

struct ChromeIconButton: View {
  let systemName: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(AppFonts.ui(size: 14, weight: .medium))
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .help(help)
  }
}
