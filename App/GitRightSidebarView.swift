import SwiftUI

struct GitRightSidebar: View {
  @ObservedObject var tabManager: WorkspaceTabManager
  @State private var resizeStartWidth: Double?

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "branch")
          .font(AppFonts.ui(size: 12, weight: .semibold))
        Text("GIT")
          .font(AppFonts.monospaced(size: 11, weight: .semibold))
          .tracking(0.7)
        Spacer()
        ChromeIconButton(systemName: "arrow.clockwise", help: "Refresh Git Sidebar") {
          tabManager.refreshRightSidebar()
        }
        if let pane = tabManager.rightSidebarPane {
          ChromeIconButton(systemName: "cursorarrow.click.2", help: "Focus Git Sidebar") {
            pane.focus()
          }
        }
        ChromeIconButton(systemName: "xmark", help: "Hide Git Sidebar") {
          tabManager.toggleRightSidebar()
        }
      }
      .foregroundStyle(.secondary)
      .padding(.leading, 12)
      .padding(.trailing, 8)
      .frame(height: 42)
      .background(AppChromeColors.sidebarBackground)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(AppChromeColors.chromeBorder)
          .frame(height: 1)
      }

      ZStack {
        if let pane = tabManager.rightSidebarPane {
          CommandSurfaceHost(pane: pane)
        } else {
          VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.slash")
              .font(AppFonts.ui(size: 24, weight: .medium))
              .foregroundStyle(.secondary)
            Text(tabManager.rightSidebarMessage ?? "Finding git repo…")
              .font(AppFonts.monospaced(size: 13, weight: .medium))
              .multilineTextAlignment(.center)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 18)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .background(AppChromeColors.mainBackground)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(Color.clear)
        .frame(width: 8)
        .contentShape(Rectangle())
        .gesture(resizeGesture)
        .help("Drag to resize Git Sidebar")
    }
  }

  private var resizeGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        let startWidth = resizeStartWidth ?? tabManager.rightSidebarState.width
        resizeStartWidth = startWidth
        tabManager.setRightSidebarWidth(startWidth - value.translation.width)
      }
      .onEnded { _ in
        resizeStartWidth = nil
      }
  }
}
