import CoreText
import Foundation
import SmoovLog
import SwiftUI

enum AppFonts {
  static let familyName = "Maple Mono NL NF"

  static func registerBundledFonts() {
    let fontURLs =
      (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
      + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
    guard !fontURLs.isEmpty else {
      SmoovLog.error("bundled fonts missing")
      return
    }

    for url in fontURLs {
      var error: Unmanaged<CFError>?
      guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
        if let error = error?.takeRetainedValue() {
          SmoovLog.error("bundled font registration failed: \(error)")
        }
        continue
      }
    }
  }

  static func ui(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .custom(familyName, size: size).weight(weight)
  }

  static func monospaced(size: CGFloat, weight: Font.Weight = .regular) -> Font {
    ui(size: size, weight: weight)
  }
}
