import Foundation

public enum PushToTalkKey: Equatable, Sendable {
  case rightOption
}

public enum PushToTalkDictationDefaults {
  public static let isEnabled = true
  public static let whisperKitModel = "openai_whisper-large-v3_turbo_954MB"
  public static let modelDownloadBase = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".smoovmux")
    .appending(path: "voice")
    .appending(path: "models")
    .appending(path: "whisperkit")
  public static let pttKey = PushToTalkKey.rightOption
}

public enum VoiceModelReadiness: Equatable, Sendable {
  case notStarted
  case preparing
  case downloading(Double?)
  case loading
  case ready
  case failed(String)

  public var isReady: Bool {
    self == .ready
  }
}

@MainActor
public protocol SpeechModelReadinessProviding: AnyObject {
  var readiness: VoiceModelReadiness { get }
}

@MainActor
public protocol StreamingSpeechTranscribing {
  /// Begins live transcription. The `onConfirmedText` callback fires on the main
  /// actor each time a new finalized text chunk is available. Chunks may carry
  /// their own leading/trailing whitespace from the underlying speech model and
  /// the caller is expected to sanitize before display.
  func startStream(onConfirmedText: @escaping @MainActor (String) -> Void) async throws

  /// Stops the stream and returns any tail of unconfirmed text the model had
  /// not yet promoted to a confirmed segment, or `nil` if there is none.
  func stopStream() async throws -> String?

  /// Aborts the stream without returning a tail.
  func cancelStream() async
}

@MainActor
public protocol ActivePaneWriting: AnyObject {
  func writeToActivePane(_ text: String)
}

public struct DictationTextSanitizer: Sendable {
  public init() {}

  public func sanitizeForPTYInsert(_ transcript: String) -> String? {
    let normalized =
      transcript
      .replacingOccurrences(of: "\r\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")

    let collapsed =
      normalized
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")

    return collapsed.isEmpty ? nil : collapsed
  }

  /// Sanitizes an incremental streaming chunk. Unlike `sanitizeForPTYInsert`,
  /// this preserves a single leading/trailing space if present so that
  /// successive chunks concatenated by the PTY retain word boundaries.
  /// Returns `nil` for whitespace-only chunks.
  public func sanitizeStreamingChunk(_ chunk: String) -> String? {
    let normalized =
      chunk
      .replacingOccurrences(of: "\r\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")

    guard normalized.contains(where: { !$0.isWhitespace }) else { return nil }

    var result = ""
    var lastWasSpace = false
    for character in normalized {
      if character.isWhitespace {
        if !lastWasSpace { result.append(" ") }
        lastWasSpace = true
      } else {
        result.append(character)
        lastWasSpace = false
      }
    }
    return result
  }
}

public enum PushToTalkDictationState: Equatable, Sendable {
  case idle
  case listening
  case transcribing
  case inserted
  case noSpeechDetected
  case failed(String)
}

@MainActor
public final class PushToTalkDictationController {
  public private(set) var state: PushToTalkDictationState = .idle

  private let transcriber: StreamingSpeechTranscribing
  private let modelReadiness: SpeechModelReadinessProviding?
  private let writer: ActivePaneWriting
  private let sanitizer: DictationTextSanitizer
  private var didWriteAnyChunk = false

  public init(
    transcriber: StreamingSpeechTranscribing,
    modelReadiness: SpeechModelReadinessProviding? = nil,
    writer: ActivePaneWriting,
    sanitizer: DictationTextSanitizer = DictationTextSanitizer()
  ) {
    self.transcriber = transcriber
    self.modelReadiness = modelReadiness
    self.writer = writer
    self.sanitizer = sanitizer
  }

  public func beginPushToTalk() async {
    guard state.canBeginRecording else { return }
    guard modelReadiness?.readiness.isReady ?? true else {
      state = .failed("Voice model is still loading")
      return
    }

    didWriteAnyChunk = false
    do {
      try await transcriber.startStream { [weak self] chunk in
        self?.handleConfirmedChunk(chunk)
      }
      state = .listening
    } catch {
      state = .failed("Couldn’t start dictation: \(error.localizedDescription)")
    }
  }

  public func endPushToTalk() async {
    guard state == .listening else { return }
    state = .transcribing

    do {
      let tail = try await transcriber.stopStream()
      if let tail, let sanitized = sanitizer.sanitizeForPTYInsert(tail) {
        writer.writeToActivePane(sanitized)
        didWriteAnyChunk = true
      }
      state = didWriteAnyChunk ? .inserted : .noSpeechDetected
    } catch {
      state = .failed("Couldn’t finish dictation: \(error.localizedDescription)")
    }
  }

  public func cancelPushToTalk() async {
    guard state == .listening || state == .transcribing else { return }
    await transcriber.cancelStream()
    state = .idle
  }

  private func handleConfirmedChunk(_ chunk: String) {
    guard let sanitized = sanitizer.sanitizeStreamingChunk(chunk) else { return }
    writer.writeToActivePane(sanitized)
    didWriteAnyChunk = true
  }
}

extension PushToTalkDictationState {
  fileprivate var canBeginRecording: Bool {
    switch self {
    case .idle, .inserted, .noSpeechDetected, .failed:
      return true
    case .listening, .transcribing:
      return false
    }
  }
}
