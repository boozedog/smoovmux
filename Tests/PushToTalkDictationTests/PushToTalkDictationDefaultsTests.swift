import Testing

@testable import PushToTalkDictation

struct PushToTalkDictationDefaultsTests {
  @Test func defaultsEnableVoiceInputWithLargeV3Turbo1GB() {
    #expect(PushToTalkDictationDefaults.isEnabled == true)
    #expect(PushToTalkDictationDefaults.whisperKitModel == "openai_whisper-large-v3_turbo_954MB")
  }

  @Test func defaultBindingIsPhysicalRightOptionKey() {
    #expect(PushToTalkDictationDefaults.pttKey == .rightOption)
  }

  @Test func defaultModelDownloadBaseIsStableSmoovmuxDirectory() {
    let path = PushToTalkDictationDefaults.modelDownloadBase.path(percentEncoded: false)

    #expect(path.hasSuffix("/.smoovmux/voice/models/whisperkit"))
  }
}
