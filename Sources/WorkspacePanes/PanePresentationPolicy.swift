import Foundation

public enum PanePresentationPolicy {
  public static func selectedTerminalTitle(
    selectedPaneId: UUID,
    titlesByPaneId: [UUID: String]
  ) -> String? {
    let title = titlesByPaneId[selectedPaneId]?.trimmingCharacters(in: .whitespacesAndNewlines)
    return title?.isEmpty == false ? title : nil
  }

  public static func windowTitle(for leaf: WorkspacePaneLeaf?, homePath: String) -> String {
    let cwd = cwdDisplay(cwd: leaf?.cwd, homePath: homePath)
    let command = leaf?.command ?? "shell"
    return "\(cwd) — \(command)"
  }

  private static func cwdDisplay(cwd: URL?, homePath: String) -> String {
    guard let path = cwd?.path else { return "~" }
    guard path.hasPrefix(homePath) else { return path }
    return "~" + path.dropFirst(homePath.count)
  }
}
