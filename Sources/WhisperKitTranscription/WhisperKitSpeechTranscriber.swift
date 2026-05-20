import Foundation
import PushToTalkDictation
import SmoovLog
@preconcurrency import WhisperKit

@MainActor
public final class WhisperKitSpeechTranscriber: StreamingSpeechTranscribing, SpeechModelReadinessProviding {
  public enum Event: Equatable, Sendable {
    case preparingModel
    case downloadingModel(Double?)
    case loadingModel
    case streaming
  }

  private let model: String
  private let downloadBase: URL
  private let onEvent: @MainActor (Event) -> Void
  private var whisperKit: WhisperKit?
  private var prepareTask: Task<Void, Error>?
  private var session: StreamingSession?
  public private(set) var readiness: VoiceModelReadiness = .notStarted

  public init(
    model: String = PushToTalkDictationDefaults.whisperKitModel,
    downloadBase: URL = PushToTalkDictationDefaults.modelDownloadBase,
    onEvent: @escaping @MainActor (Event) -> Void = { _ in }
  ) {
    self.model = model
    self.downloadBase = downloadBase
    self.onEvent = onEvent
  }

  public func prepare() async throws {
    SmoovLog.info("dictation prepare called model=\(model) downloadBase=\(downloadBase.path)")
    _ = try await pipeline()
  }

  public func startStream(onConfirmedText: @escaping @MainActor (String) -> Void) async throws {
    guard session == nil else { return }
    let pipe = try await pipeline()
    _ = onConfirmedText

    try pipe.audioProcessor.startRecordingLive(inputDeviceID: nil, callback: nil)
    session = StreamingSession(audioProcessor: pipe.audioProcessor, pipe: pipe)
    onEvent(.streaming)
    SmoovLog.info("dictation capture started model=\(model)")
  }

  public func stopStream() async throws -> String? {
    guard let session else { return nil }
    self.session = nil
    let samples = Array(session.audioProcessor.audioSamples)
    session.audioProcessor.stopRecording()
    SmoovLog.info("dictation capture stopped samples=\(samples.count)")
    guard !samples.isEmpty else { return nil }
    let results = try await session.pipe.transcribe(audioArray: samples)
    let transcript = results.map(\.text).joined(separator: " ")
    SmoovLog.info("dictation transcribed chars=\(transcript.count)")
    return transcript.isEmpty ? nil : transcript
  }

  public func cancelStream() async {
    guard let session else { return }
    self.session = nil
    session.audioProcessor.stopRecording()
    SmoovLog.info("dictation capture cancelled")
  }

  private func pipeline() async throws -> WhisperKit {
    if let whisperKit {
      return whisperKit
    }
    if let prepareTask {
      try await prepareTask.value
      guard let whisperKit else {
        throw WhisperKitSpeechTranscriberError.modelDidNotLoad
      }
      return whisperKit
    }
    let task = Task { @MainActor in
      _ = try await loadPipeline()
    }
    prepareTask = task
    do {
      try await task.value
      prepareTask = nil
      guard let whisperKit else {
        throw WhisperKitSpeechTranscriberError.modelDidNotLoad
      }
      return whisperKit
    } catch {
      prepareTask = nil
      readiness = .failed(error.localizedDescription)
      throw error
    }
  }

  private func loadPipeline() async throws -> WhisperKit {
    let started = Date()
    onEvent(.preparingModel)
    readiness = .preparing
    try FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)

    let modelFolder = localModelFolder
    SmoovLog.info(
      "dictation model local folder path=\(modelFolder.path) exists=\(FileManager.default.fileExists(atPath: modelFolder.path))"
    )
    if !FileManager.default.fileExists(atPath: modelFolder.path) {
      SmoovLog.info(
        "dictation model missing locally; starting WhisperKit download model=\(model) base=\(downloadBase.path)")
      let downloadedFolder = try await WhisperKit.download(variant: model, downloadBase: downloadBase) {
        [weak self, onEvent] progress in
        let fraction =
          progress.totalUnitCount > 0
          ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
          : nil
        Task { @MainActor in
          self?.readiness = .downloadingModelReadiness(fraction)
          onEvent(.downloadingModel(fraction))
        }
      }
      guard downloadedFolder == modelFolder else {
        throw WhisperKitSpeechTranscriberError.unexpectedModelFolder(downloadedFolder.path)
      }
      SmoovLog.info("dictation model download completed path=\(downloadedFolder.path)")
    } else {
      SmoovLog.info("dictation model found locally; skipping WhisperKit download")
    }

    onEvent(.loadingModel)
    readiness = .loading
    SmoovLog.info("dictation model load starting model=\(model) folder=\(modelFolder.path)")
    let pipe = try await WhisperKit(
      model: model,
      downloadBase: downloadBase,
      modelFolder: modelFolder.path,
      tokenizerFolder: downloadBase,
      verbose: false,
      prewarm: false,
      load: true,
      download: false
    )
    whisperKit = pipe
    readiness = .ready
    SmoovLog.info(
      "dictation model load completed elapsed=\(String(format: "%.2f", Date().timeIntervalSince(started)))s")
    return pipe
  }

  private var localModelFolder: URL {
    downloadBase
      .appending(path: "models")
      .appending(path: "argmaxinc")
      .appending(path: "whisperkit-coreml")
      .appending(path: model)
  }
}

@MainActor
private final class StreamingSession {
  let audioProcessor: any AudioProcessing
  let pipe: WhisperKit

  init(audioProcessor: any AudioProcessing, pipe: WhisperKit) {
    self.audioProcessor = audioProcessor
    self.pipe = pipe
  }
}

private enum WhisperKitSpeechTranscriberError: LocalizedError {
  case modelDidNotLoad
  case tokenizerUnavailable
  case unexpectedModelFolder(String)

  var errorDescription: String? {
    switch self {
    case .modelDidNotLoad:
      return "Speech model did not load"
    case .tokenizerUnavailable:
      return "Speech tokenizer is not loaded"
    case .unexpectedModelFolder(let path):
      return "Speech model downloaded to unexpected path: \(path)"
    }
  }
}

extension VoiceModelReadiness {
  fileprivate static func downloadingModelReadiness(_ fraction: Double?) -> VoiceModelReadiness {
    .downloading(fraction)
  }
}
