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

  @Test("privacy-safe terminal metadata updates are tracked")
  func privacySafeMetadataUpdatesAreTracked() {
    var status = TerminalScreenStatus()
    let color = TerminalColorChange(kind: .background, red: 1, green: 2, blue: 3)
    let scrollbar = TerminalScrollbar(total: 200, offset: 50, length: 20)

    status.apply(.desktopNotification(TerminalNotification(title: "build", body: "done")))
    status.apply(.mouseOverLink("https://example.com"))
    status.apply(.colorChanged(color))
    status.apply(.configReloaded(soft: true))
    status.apply(.configChanged)
    status.apply(.searchStarted(needle: "warning"))
    status.apply(.searchTotal(3))
    status.apply(.searchSelected(2))
    status.apply(.scrollbarChanged(scrollbar))

    #expect(status.lastNotification == TerminalNotification(title: "build", body: "done"))
    #expect(status.hoveredURL == "https://example.com")
    #expect(status.lastColorChange == color)
    #expect(status.configReloadCount == 1)
    #expect(status.configChangeCount == 1)
    #expect(status.search == TerminalSearchState(needle: "warning", total: 3, selected: 2))
    #expect(status.scrollbar == scrollbar)
  }

  @Test("search and hover metadata can be cleared")
  func searchAndHoverMetadataCanBeCleared() {
    var status = TerminalScreenStatus()

    status.apply(.mouseOverLink("https://example.com"))
    status.apply(.searchStarted(needle: "warning"))
    status.apply(.searchTotal(3))
    status.apply(.searchSelected(1))
    status.apply(.mouseOverLink(nil))
    status.apply(.searchEnded)

    #expect(status.hoveredURL == nil)
    #expect(status.search == nil)
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
