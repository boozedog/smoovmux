import Testing

@testable import SessionCore

@Suite("Terminal surface sizing")
struct TerminalSurfaceSizingTests {
  @Test("backing pixels are recomputed when only display scale changes")
  func backingPixelsChangeWithScale() {
    let retina = TerminalSurfaceSizing.backingPixelSize(
      widthPoints: 1_200,
      heightPoints: 800,
      backingScaleFactor: 2
    )
    let standard = TerminalSurfaceSizing.backingPixelSize(
      widthPoints: 1_200,
      heightPoints: 800,
      backingScaleFactor: 1
    )

    #expect(retina.width == 2_400)
    #expect(retina.height == 1_600)
    #expect(standard.width == 1_200)
    #expect(standard.height == 800)
  }

  @Test("surface metrics include content scale used for the backing conversion")
  func surfaceMetricsIncludeContentScale() {
    let metrics = TerminalSurfaceSizing.backingMetrics(
      widthPoints: 600,
      heightPoints: 400,
      backingScaleFactor: 2
    )

    #expect(metrics.pixelSize.width == 1_200)
    #expect(metrics.pixelSize.height == 800)
    #expect(metrics.contentScaleX == 2)
    #expect(metrics.contentScaleY == 2)
  }

  @Test("fractional backing pixels are rounded to the nearest whole pixel")
  func fractionalPixelsRoundToNearestWholePixel() {
    let pixels = TerminalSurfaceSizing.backingPixelSize(
      widthPoints: 333.5,
      heightPoints: 222.25,
      backingScaleFactor: 1.5
    )

    #expect(pixels.width == 500)
    #expect(pixels.height == 333)
  }
}
