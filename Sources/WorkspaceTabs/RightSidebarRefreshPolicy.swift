import Foundation

public enum RightSidebarRefreshPolicy {
  public static func shouldOpenPane(
    currentGitRoot: URL?,
    requestedGitRoot: URL,
    hasExistingPane: Bool,
    forceRestart: Bool
  ) -> Bool {
    guard !forceRestart else { return true }
    guard hasExistingPane else { return true }
    return currentGitRoot?.standardizedFileURL != requestedGitRoot.standardizedFileURL
  }
}
