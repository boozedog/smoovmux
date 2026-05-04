public enum GitSidebarToolbarAction: Equatable, Sendable {
  case refresh
  case hide
}

public enum GitSidebarToolbarPolicy {
  public static func actions(hasPane: Bool) -> [GitSidebarToolbarAction] {
    [.refresh, .hide]
  }
}
