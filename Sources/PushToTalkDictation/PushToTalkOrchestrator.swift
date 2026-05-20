import Foundation

@MainActor
public protocol DictationOverlayPresenting: AnyObject {
  func showDictationOverlay(message: String)
  func updateDictationOverlay(message: String)
  func hideDictationOverlay()
}

/// Orchestrates the press/release/end/hide lifecycle of push-to-talk dictation.
///
/// Owns the begin task, the end task, and the hide timer so there is exactly
/// one path that ends a recording and exactly one pending hide at a time. The
/// surface view stays a thin adapter — it only forwards key events and
/// implements the overlay protocol against AppKit views.
@MainActor
public final class PushToTalkOrchestrator {
  private let controller: PushToTalkDictationController
  private let overlay: DictationOverlayPresenting
  private let modelReadiness: SpeechModelReadinessProviding?
  private let isKeyStillHeld: @MainActor () -> Bool
  private let readinessOverlayMessage: @MainActor (VoiceModelReadiness) -> String
  private let sleep: @Sendable (Duration) async -> Void

  private var beginTask: Task<Void, Never>?
  private var endTask: Task<Void, Never>?
  private var hideTask: Task<Void, Never>?

  public init(
    controller: PushToTalkDictationController,
    overlay: DictationOverlayPresenting,
    modelReadiness: SpeechModelReadinessProviding?,
    isKeyStillHeld: @escaping @MainActor () -> Bool,
    readinessOverlayMessage: @escaping @MainActor (VoiceModelReadiness) -> String,
    sleep: @escaping @Sendable (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    }
  ) {
    self.controller = controller
    self.overlay = overlay
    self.modelReadiness = modelReadiness
    self.isKeyStillHeld = isKeyStillHeld
    self.readinessOverlayMessage = readinessOverlayMessage
    self.sleep = sleep
  }

  public func handle(isPressed: Bool) {
    if isPressed {
      press()
    } else {
      release()
    }
  }

  private func press() {
    cancelHide()

    if let readiness = modelReadiness?.readiness, !readiness.isReady {
      overlay.showDictationOverlay(message: readinessOverlayMessage(readiness))
      scheduleHide(after: .seconds(2))
      return
    }

    // If a previous cycle is still winding down, ignore — release will close
    // it out. A fresh press while in-flight would otherwise stack begin tasks.
    guard beginTask == nil, endTask == nil else { return }

    overlay.showDictationOverlay(message: "Starting microphone…\nKeep holding Right Option")
    beginTask = Task { [weak self] in
      guard let self else { return }
      await controller.beginPushToTalk()
      // Only advertise "Recording…" if (a) we actually entered listening and
      // (b) the key is still held. If the key was already released, the end
      // path owns the next overlay update.
      if controller.state == .listening, isKeyStillHeld() {
        overlay.updateDictationOverlay(message: "Recording…\nRelease Right Option to transcribe")
      }
      beginTask = nil
    }
  }

  private func release() {
    // Nothing in flight — nothing to do. Prevents stray release events (e.g.
    // a flagsChanged firing without a matching press) from spawning end tasks.
    guard beginTask != nil || controller.state == .listening else { return }
    guard endTask == nil else { return }

    let pendingBegin = beginTask
    endTask = Task { [weak self] in
      guard let self else { return }
      await pendingBegin?.value
      defer { endTask = nil }
      guard controller.state == .listening else {
        // Begin never reached listening (failed, or readiness flipped). Show
        // whatever final state the controller landed on.
        showFinalState()
        return
      }
      overlay.updateDictationOverlay(message: "Transcribing…")
      await controller.endPushToTalk()
      showFinalState()
    }
  }

  private func showFinalState() {
    switch controller.state {
    case .inserted:
      overlay.updateDictationOverlay(message: "Inserted dictation")
      scheduleHide(after: .seconds(1))
    case .noSpeechDetected:
      overlay.updateDictationOverlay(message: "No speech detected")
      scheduleHide(after: .milliseconds(1500))
    case .failed(let message):
      overlay.updateDictationOverlay(message: message)
      scheduleHide(after: .milliseconds(2500))
    case .idle, .listening, .transcribing:
      cancelHide()
      overlay.hideDictationOverlay()
    }
  }

  private func scheduleHide(after delay: Duration) {
    hideTask?.cancel()
    let sleepFn = sleep
    hideTask = Task { [weak self] in
      await sleepFn(delay)
      guard !Task.isCancelled else { return }
      guard let self else { return }
      overlay.hideDictationOverlay()
      hideTask = nil
    }
  }

  private func cancelHide() {
    hideTask?.cancel()
    hideTask = nil
  }
}
