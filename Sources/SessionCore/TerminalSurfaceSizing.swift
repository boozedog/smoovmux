public struct TerminalSurfacePixelSize: Equatable, Sendable {
  public let width: UInt32
  public let height: UInt32

  public init(width: UInt32, height: UInt32) {
    self.width = width
    self.height = height
  }
}

public struct TerminalSurfaceBackingMetrics: Equatable, Sendable {
  public let pixelSize: TerminalSurfacePixelSize
  public let contentScaleX: Double
  public let contentScaleY: Double

  public init(pixelSize: TerminalSurfacePixelSize, contentScaleX: Double, contentScaleY: Double) {
    self.pixelSize = pixelSize
    self.contentScaleX = contentScaleX
    self.contentScaleY = contentScaleY
  }
}

public enum TerminalSurfaceSizing {
  public static func backingPixelSize(
    widthPoints: Double,
    heightPoints: Double,
    backingScaleFactor: Double
  ) -> TerminalSurfacePixelSize {
    backingMetrics(
      widthPoints: widthPoints,
      heightPoints: heightPoints,
      backingScaleFactor: backingScaleFactor
    ).pixelSize
  }

  public static func backingMetrics(
    widthPoints: Double,
    heightPoints: Double,
    backingScaleFactor: Double
  ) -> TerminalSurfaceBackingMetrics {
    TerminalSurfaceBackingMetrics(
      pixelSize: TerminalSurfacePixelSize(
        width: pixelCount(points: widthPoints, scale: backingScaleFactor),
        height: pixelCount(points: heightPoints, scale: backingScaleFactor)
      ),
      contentScaleX: validScale(backingScaleFactor),
      contentScaleY: validScale(backingScaleFactor)
    )
  }

  private static func pixelCount(points: Double, scale: Double) -> UInt32 {
    guard points.isFinite, scale.isFinite, points > 0, scale > 0 else { return 0 }
    let rounded = (points * scale).rounded()
    guard rounded < Double(UInt32.max) else { return UInt32.max }
    return UInt32(rounded)
  }

  private static func validScale(_ scale: Double) -> Double {
    guard scale.isFinite, scale > 0 else { return 1 }
    return scale
  }
}
