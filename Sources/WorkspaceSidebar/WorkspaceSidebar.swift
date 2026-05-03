public struct WorkspaceRightSidebarState: Codable, Equatable, Sendable {
  public static let minimumWidth = 240.0
  public static let maximumWidth = 640.0

  public var isOpen: Bool
  public var width: Double

  public init(isOpen: Bool = false, width: Double = 320) {
    self.isOpen = isOpen
    self.width = Self.clamp(width)
  }

  public mutating func setWidth(_ width: Double) {
    self.width = Self.clamp(width)
  }

  private static func clamp(_ width: Double) -> Double {
    max(minimumWidth, min(width, maximumWidth))
  }
}
