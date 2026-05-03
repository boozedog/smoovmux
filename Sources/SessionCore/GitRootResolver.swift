import Foundation

public struct GitRootResolver: Sendable {
  public init() {}

  public func resolve(cwd: URL) async throws -> URL? {
    let gitURL = try BinaryResolver.resolve("git")
    let process = Process()
    process.executableURL = gitURL
    process.arguments = ["-C", cwd.path, "rev-parse", "--show-toplevel"]
    process.standardInput = nil

    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()

    return try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { process in
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
          continuation.resume(returning: nil)
          return
        }
        let path = String(data: data, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else {
          continuation.resume(returning: nil)
          return
        }
        continuation.resume(returning: URL(fileURLWithPath: path))
      }

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}
