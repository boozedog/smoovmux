import SwiftUI

struct WorkspaceMainArea: View {
  @ObservedObject var tabManager: WorkspaceTabManager

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        ChromeIconButton(systemName: "sidebar.left", help: "Toggle Screens Sidebar") {
          tabManager.toggleLeftSidebar()
        }
        HStack(spacing: 8) {
          Text(tabManager.selectedPaneCwdDisplay)
            .foregroundStyle(.secondary)
          Text("•")
            .foregroundStyle(.secondary.opacity(0.7))
          Text(tabManager.topBarTitle)
            .foregroundStyle(.primary.opacity(0.92))
        }
        .font(AppFonts.monospaced(size: 13, weight: .semibold))
        .lineLimit(1)
        .truncationMode(.tail)
        Spacer()
        ChromeIconButton(systemName: "rectangle.split.2x1", help: "Split Right") {
          tabManager.showLauncher(action: .splitRight)
        }
        ChromeIconButton(systemName: "rectangle.split.1x2", help: "Split Down") {
          tabManager.showLauncher(action: .splitDown)
        }
        ChromeIconButton(
          systemName: tabManager.selectedPaneIsZoomed
            ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
          help: tabManager.selectedPaneIsZoomed ? "Unzoom Pane" : "Zoom Pane"
        ) {
          tabManager.toggleSelectedPaneZoom()
        }
        ChromeIconButton(systemName: "sidebar.right", help: "Toggle Git Sidebar") {
          tabManager.toggleRightSidebar()
        }
      }
      .padding(.leading, 12)
      .padding(.trailing, 12)
      .frame(height: 42)
      .background {
        WindowDragArea()
          .background(AppChromeColors.sidebarBackground)
      }
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(AppChromeColors.chromeBorder)
          .frame(height: 1)
      }

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
