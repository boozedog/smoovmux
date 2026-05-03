import Foundation
import Testing

@testable import SessionCore

@Suite("Terminal transfer policy")
struct TerminalTransferPolicyTests {
  @Test("shell quoting leaves safe paths readable")
  func shellQuotingLeavesSafePathsReadable() {
    #expect(TerminalTransferPolicy.shellQuotedPath("/Users/david/src/file.txt") == "/Users/david/src/file.txt")
  }

  @Test("shell quoting protects spaces and single quotes")
  func shellQuotingProtectsSpacesAndSingleQuotes() {
    #expect(
      TerminalTransferPolicy.shellQuotedPath("/Users/david/Desktop/it's fine.png")
        == "'/Users/david/Desktop/it'\\''s fine.png'"
    )
  }

  @Test("path payload joins multiple quoted paths")
  func pathPayloadJoinsMultipleQuotedPaths() {
    let paths = [
      URL(fileURLWithPath: "/tmp/one.txt"),
      URL(fileURLWithPath: "/tmp/two words.txt"),
    ]

    #expect(TerminalTransferPolicy.pathPayload(for: paths) == "/tmp/one.txt '/tmp/two words.txt'")
  }

  @Test("terminal image store writes supported image bytes with extension")
  func terminalImageStoreWritesSupportedImageBytesWithExtension() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = TerminalImageStore(rootDirectory: root)
    let bytes = Data([0x89, 0x50, 0x4e, 0x47])

    let url = try store.writeImage(
      bytes, contentType: "public.png", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

    #expect(url.lastPathComponent == "00000000-0000-0000-0000-000000000001.png")
    #expect(try Data(contentsOf: url) == bytes)
  }

  @Test("terminal image store rejects unsupported and empty image data")
  func terminalImageStoreRejectsUnsupportedAndEmptyImageData() throws {
    let store = TerminalImageStore(
      rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    )

    #expect(throws: TerminalImageStore.Error.unsupportedContentType) {
      try store.writeImage(Data([1]), contentType: "com.adobe.pdf")
    }
    #expect(throws: TerminalImageStore.Error.emptyData) {
      try store.writeImage(Data(), contentType: "public.png")
    }
  }
}
