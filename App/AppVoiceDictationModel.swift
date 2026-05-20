import AVFoundation
import Foundation
import PushToTalkDictation
import SmoovLog
import SwiftUI
import WhisperKitTranscription

@MainActor
final class AppVoiceDictationModel: ObservableObject, SpeechModelReadinessProviding {
  static let shared = AppVoiceDictationModel()

  @Published private(set) var readiness: VoiceModelReadiness = .notStarted

  lazy var transcriber: WhisperKitSpeechTranscriber = WhisperKitSpeechTranscriber { [weak self] event in
    self?.handle(event)
  }

  private var prepareTask: Task<Void, Never>?
  private var hasStartedLoading = false

  private init() {}

  func prepareAtLaunch() {
    guard prepareTask == nil else { return }
    SmoovLog.info("dictation model prepare requested at app launch")
    requestMicrophoneAccessIfNeeded()
    prepareTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await transcriber.prepare()
        readiness = .ready
        SmoovLog.info("dictation model ready")
      } catch {
        readiness = .failed(error.localizedDescription)
        SmoovLog.error(
          "dictation model prepare failed type=\(String(describing: type(of: error))) description=\(error.localizedDescription) debug=\(String(reflecting: error))"
        )
      }
    }
  }

  private func handle(_ event: WhisperKitSpeechTranscriber.Event) {
    SmoovLog.info("dictation whisper event=\(event.logDescription)")
    switch event {
    case .preparingModel:
      readiness = .preparing
    case .downloadingModel(let fraction):
      guard !hasStartedLoading else { return }
      readiness = .downloading(fraction)
    case .loadingModel:
      hasStartedLoading = true
      readiness = .loading
    case .streaming:
      break
    }
  }

  private func requestMicrophoneAccessIfNeeded() {
    let status = AVAudioApplication.shared.recordPermission
    guard status == .undetermined else {
      SmoovLog.info("dictation microphone permission status=\(status.logDescription)")
      return
    }
    SmoovLog.info("dictation microphone permission undetermined; requesting at launch")
    AVAudioApplication.requestRecordPermission { granted in
      SmoovLog.info("dictation microphone permission resolved granted=\(granted)")
    }
  }
}

extension AVAudioApplication.recordPermission {
  fileprivate var logDescription: String {
    switch self {
    case .undetermined: return "undetermined"
    case .denied: return "denied"
    case .granted: return "granted"
    @unknown default: return "unknown"
    }
  }
}

extension VoiceModelReadiness {
  var sidebarText: String {
    switch self {
    case .notStarted:
      return "Starting"
    case .preparing:
      return "Preparing"
    case .downloading(let fraction):
      if let fraction {
        let percent = max(0, min(100, Int((fraction * 100).rounded())))
        return "Downloading \(percent)%"
      }
      return "Downloading"
    case .loading:
      return "Loading"
    case .ready:
      return "Ready"
    case .failed:
      return "Unavailable"
    }
  }

  var overlayText: String {
    switch self {
    case .notStarted, .preparing:
      return "Voice model is preparing"
    case .downloading(let fraction):
      if let fraction {
        let percent = max(0, min(100, Int((fraction * 100).rounded())))
        return "Voice model is downloading\n\(percent)%"
      }
      return "Voice model is downloading"
    case .loading:
      return "Voice model is loading\nCore ML may compile on first use"
    case .ready:
      return "Voice ready"
    case .failed(let message):
      return "Voice unavailable\n\(message)"
    }
  }
}

extension WhisperKitSpeechTranscriber.Event {
  fileprivate var logDescription: String {
    switch self {
    case .preparingModel:
      return "preparingModel"
    case .downloadingModel(let fraction):
      if let fraction {
        return "downloadingModel(\(Int((fraction * 100).rounded()))%)"
      }
      return "downloadingModel"
    case .loadingModel:
      return "loadingModel"
    case .streaming:
      return "streaming"
    }
  }
}
