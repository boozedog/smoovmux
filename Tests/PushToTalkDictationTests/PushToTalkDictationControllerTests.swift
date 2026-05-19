import Foundation
import Testing

@testable import PushToTalkDictation

@MainActor
struct PushToTalkDictationControllerTests {
  @Test func confirmedChunksAreWrittenAsTheyArrive() async {
    let transcriber = FakeStreamingTranscriber()
    let writer = FakeWriter()
    let controller = PushToTalkDictationController(
      transcriber: transcriber,
      writer: writer
    )

    await controller.beginPushToTalk()
    #expect(controller.state == .listening)

    transcriber.emitConfirmed(" hello")
    transcriber.emitConfirmed(" world")

    #expect(writer.writes == [" hello", " world"])
  }

  @Test func tailIsWrittenOnEnd() async {
    let transcriber = FakeStreamingTranscriber()
    let writer = FakeWriter()
    let controller = PushToTalkDictationController(
      transcriber: transcriber,
      writer: writer
    )

    await controller.beginPushToTalk()
    transcriber.emitConfirmed(" hello")
    transcriber.tail = " world "
    await controller.endPushToTalk()

    #expect(writer.writes == [" hello", "world"])
    #expect(controller.state == .inserted)
  }

  @Test func endWithNoConfirmedAndNoTailMarksNoSpeechDetected() async {
    let transcriber = FakeStreamingTranscriber()
    let writer = FakeWriter()
    let controller = PushToTalkDictationController(
      transcriber: transcriber,
      writer: writer
    )

    await controller.beginPushToTalk()
    await controller.endPushToTalk()

    #expect(writer.writes.isEmpty)
    #expect(controller.state == .noSpeechDetected)
  }

  @Test func whitespaceOnlyChunksAreNotWritten() async {
    let transcriber = FakeStreamingTranscriber()
    let writer = FakeWriter()
    let controller = PushToTalkDictationController(
      transcriber: transcriber,
      writer: writer
    )

    await controller.beginPushToTalk()
    transcriber.emitConfirmed("   \n  ")
    transcriber.emitConfirmed(" real")
    await controller.endPushToTalk()

    #expect(writer.writes == [" real"])
  }

  @Test func newlinesInChunksAreReplacedWithSpaces() async {
    let transcriber = FakeStreamingTranscriber()
    let writer = FakeWriter()
    let controller = PushToTalkDictationController(
      transcriber: transcriber,
      writer: writer
    )

    await controller.beginPushToTalk()
    transcriber.emitConfirmed(" line one\nline two")
    await controller.endPushToTalk()

    #expect(writer.writes == [" line one line two"])
    #expect(!writer.writes[0].contains("\n"))
  }

  @Test func startStreamErrorIsSurfaced() async {
    let transcriber = FakeStreamingTranscriber()
    transcriber.startError = TestError.failed
    let writer = FakeWriter()
    let controller = PushToTalkDictationController(
      transcriber: transcriber,
      writer: writer
    )

    await controller.beginPushToTalk()

    #expect(writer.writes.isEmpty)
    #expect(controller.state.isFailed)
  }

  @Test func cancelStopsStreamAndDoesNotWriteTail() async {
    let transcriber = FakeStreamingTranscriber()
    transcriber.tail = " unconfirmed"
    let writer = FakeWriter()
    let controller = PushToTalkDictationController(
      transcriber: transcriber,
      writer: writer
    )

    await controller.beginPushToTalk()
    transcriber.emitConfirmed(" hello")
    await controller.cancelPushToTalk()

    #expect(writer.writes == [" hello"])
    #expect(transcriber.cancelCount == 1)
    #expect(controller.state == .idle)
  }

  @Test func beginDoesNotStartStreamUntilModelIsReady() async {
    let transcriber = FakeStreamingTranscriber()
    let readiness = FakeModelReadiness(readiness: .loading)
    let controller = PushToTalkDictationController(
      transcriber: transcriber,
      modelReadiness: readiness,
      writer: FakeWriter()
    )

    await controller.beginPushToTalk()

    #expect(transcriber.startCount == 0)
    #expect(controller.state == .failed("Voice model is still loading"))
  }

  @Test func beginIsIgnoredWhileAlreadyListening() async {
    let transcriber = FakeStreamingTranscriber()
    let controller = PushToTalkDictationController(
      transcriber: transcriber,
      writer: FakeWriter()
    )

    await controller.beginPushToTalk()
    await controller.beginPushToTalk()

    #expect(transcriber.startCount == 1)
    #expect(controller.state == .listening)
  }
}

private enum TestError: Error {
  case failed
}

@MainActor
private final class FakeStreamingTranscriber: StreamingSpeechTranscribing {
  var startCount = 0
  var stopCount = 0
  var cancelCount = 0
  var startError: Error?
  var tail: String?
  private var onConfirmedText: (@MainActor (String) -> Void)?

  func startStream(onConfirmedText: @escaping @MainActor (String) -> Void) async throws {
    startCount += 1
    if let startError {
      throw startError
    }
    self.onConfirmedText = onConfirmedText
  }

  func stopStream() async throws -> String? {
    stopCount += 1
    onConfirmedText = nil
    return tail
  }

  func cancelStream() async {
    cancelCount += 1
    onConfirmedText = nil
  }

  func emitConfirmed(_ text: String) {
    onConfirmedText?(text)
  }
}

@MainActor
private final class FakeWriter: ActivePaneWriting {
  var writes: [String] = []

  func writeToActivePane(_ text: String) {
    writes.append(text)
  }
}

@MainActor
private final class FakeModelReadiness: SpeechModelReadinessProviding {
  var readiness: VoiceModelReadiness

  init(readiness: VoiceModelReadiness) {
    self.readiness = readiness
  }
}

extension PushToTalkDictationState {
  fileprivate var isFailed: Bool {
    if case .failed = self { return true }
    return false
  }
}
