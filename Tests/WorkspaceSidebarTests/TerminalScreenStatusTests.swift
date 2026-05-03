import Testing
import WorkspaceSidebar

@Suite("Terminal screen status")
struct TerminalScreenStatusTests {
  @Test("bell increments attention count")
  func bellIncrementsAttentionCount() {
    var status = TerminalScreenStatus()

    status.apply(.bell)
    status.apply(.bell)

    #expect(status.bellCount == 2)
  }

  @Test("progress stores clamped percent and clears on nil")
  func progressStoresClampedPercentAndClearsOnNil() {
    var status = TerminalScreenStatus()

    status.apply(.progressChanged(140))
    #expect(status.progressPercent == 100)

    status.apply(.progressChanged(-10))
    #expect(status.progressPercent == 0)

    status.apply(.progressChanged(nil))
    #expect(status.progressPercent == nil)
  }

  @Test("command and child exits are tracked separately")
  func commandAndChildExitsAreTrackedSeparately() {
    var status = TerminalScreenStatus()

    status.apply(.commandFinished(exitCode: 7))
    status.apply(.childExited(exitCode: 9))

    #expect(status.lastCommandExitCode == 7)
    #expect(status.childExitCode == 9)
  }

  @Test("renderer health updates")
  func rendererHealthUpdates() {
    var status = TerminalScreenStatus()

    status.apply(.rendererHealthChanged(healthy: false))
    #expect(!status.rendererIsHealthy)

    status.apply(.rendererHealthChanged(healthy: true))
    #expect(status.rendererIsHealthy)
  }

  @Test("bell attention can be cleared independently")
  func bellAttentionCanBeCleared() {
    var status = TerminalScreenStatus()
    status.apply(.bell)
    status.apply(.commandFinished(exitCode: 1))

    status.clearBellAttention()

    #expect(status.bellCount == 0)
    #expect(status.lastCommandExitCode == 1)
  }

  @Test("successful command finish can be cleared without hiding failures")
  func successfulCommandFinishCanBeCleared() {
    var success = TerminalScreenStatus()
    success.apply(.commandFinished(exitCode: 0))
    success.clearSuccessfulCommandFinished()
    #expect(success.lastCommandExitCode == nil)

    var failure = TerminalScreenStatus()
    failure.apply(.commandFinished(exitCode: 2))
    failure.clearSuccessfulCommandFinished()
    #expect(failure.lastCommandExitCode == 2)
  }

  @Test("indicator prioritizes renderer health, child exit, progress, bell, command finish")
  func indicatorPriority() {
    var status = TerminalScreenStatus()
    #expect(status.indicator == nil)

    status.apply(.commandFinished(exitCode: 0))
    #expect(status.indicator == .commandFinished(exitCode: 0))

    status.apply(.bell)
    #expect(status.indicator == .bell(count: 1))

    status.apply(.progressChanged(42))
    #expect(status.indicator == .progress(percent: 42))

    status.apply(.childExited(exitCode: 9))
    #expect(status.indicator == .childExited(exitCode: 9))

    status.apply(.rendererHealthChanged(healthy: false))
    #expect(status.indicator == .rendererUnhealthy)
  }
}
