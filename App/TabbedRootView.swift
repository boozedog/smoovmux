import PaneLauncher
import SwiftUI

struct TabbedRootView: View {
  @ObservedObject var tabManager: WorkspaceTabManager

  var body: some View {
    ZStack {
      HStack(spacing: 0) {
        if tabManager.leftSidebarState.isOpen {
          WorkspaceTabSidebar(tabManager: tabManager)
            .frame(width: 184)
        }

        WorkspaceMainArea(tabManager: tabManager)
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        if tabManager.rightSidebarState.isOpen {
          GitRightSidebar(tabManager: tabManager)
            .frame(width: tabManager.rightSidebarState.width)
        }
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
