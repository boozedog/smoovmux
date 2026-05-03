import Foundation

public enum RightSidebarAutoOpenPolicy {
  public static func shouldOpen(
    isSidebarOpen: Bool,
    requestedCwd: URL,
    currentActiveCwd: URL?,
    resolvedGitRoot: URL?
  ) -> Bool {
    guard !isSidebarOpen else { return false }
    guard resolvedGitRoot != nil else { return false }
    guard let currentActiveCwd else { return false }
    return normalizedPath(currentActiveCwd) == normalizedPath(requestedCwd)
  }

  private static func normalizedPath(_ url: URL) -> String {
    (url.path as NSString).standardizingPath
  }
}
