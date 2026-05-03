import Foundation

public enum TerminalTransferPolicy {
  public static func shellQuotedPath(_ path: String) -> String {
    guard !path.isEmpty else { return "''" }
    let safeCharacters = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-./:=,@%")
    if path.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
      return path
    }
    return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  public static func pathPayload(for urls: [URL]) -> String? {
    let payload =
      urls
      .map(\.path)
      .filter { !$0.isEmpty }
      .map(shellQuotedPath(_:))
      .joined(separator: " ")
    return TerminalTextInputPolicy.textPayload(payload)
  }
}

public struct TerminalImageStore: Sendable {
  public enum Error: Swift.Error, Equatable {
    case emptyData
    case unsupportedContentType
  }

  public let rootDirectory: URL

  public init(rootDirectory: URL = TerminalImageStore.defaultRootDirectory) {
    self.rootDirectory = rootDirectory
  }

  public static var defaultRootDirectory: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("smoovmux", isDirectory: true)
      .appendingPathComponent("dropped-images", isDirectory: true)
  }

  public func writeImage(
    _ data: Data,
    contentType: String,
    id: UUID = UUID(),
    fileManager: FileManager = .default
  ) throws -> URL {
    guard !data.isEmpty else { throw Error.emptyData }
    guard let ext = Self.fileExtension(for: contentType) else {
      throw Error.unsupportedContentType
    }

    try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    let url = rootDirectory.appendingPathComponent(id.uuidString).appendingPathExtension(ext)
    try data.write(to: url, options: [.atomic])
    return url
  }

  public func cleanupFiles(olderThan cutoff: Date, fileManager: FileManager = .default) throws {
    guard
      let enumerator = fileManager.enumerator(
        at: rootDirectory,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
      )
    else { return }

    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
      guard values.isRegularFile == true, let modified = values.contentModificationDate, modified < cutoff else {
        continue
      }
      try fileManager.removeItem(at: url)
    }
  }

  public static func fileExtension(for contentType: String) -> String? {
    switch contentType {
    case "public.png", "png", "image/png":
      return "png"
    case "public.jpeg", "public.jpg", "jpeg", "jpg", "image/jpeg":
      return "jpg"
    case "com.compuserve.gif", "public.gif", "gif", "image/gif":
      return "gif"
    case "org.webmproject.webp", "public.webp", "webp", "image/webp":
      return "webp"
    case "public.tiff", "tiff", "tif", "image/tiff":
      return "tiff"
    default:
      return nil
    }
  }
}
