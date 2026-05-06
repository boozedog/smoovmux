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

  @Test("acknowledging selection clears attention and completed process indicators but not renderer health")
  func acknowledgingSelectionClearsAttentionAndCompletedProcessIndicators() {
    var status = TerminalScreenStatus()
    status.apply(.bell)
    status.apply(.commandFinished(exitCode: 0))
    status.apply(.childExited(exitCode: 9))
    status.apply(.rendererHealthChanged(healthy: false))

    status.acknowledgeSelection()

    #expect(status.bellCount == 0)
    #expect(status.lastCommandExitCode == nil)
    #expect(status.childExitCode == nil)
    #expect(!status.rendererIsHealthy)
  }

  @Test("indicator descriptions explain the visible status")
  func indicatorDescriptionsExplainVisibleStatus() {
    #expect(TerminalScreenIndicator.bell(count: 2).accessibilityLabel == "Terminal bell, 2 alerts")
    #expect(TerminalScreenIndicator.progress(percent: 42).accessibilityLabel == "Terminal progress 42 percent")
    #expect(TerminalScreenIndicator.commandFinished(exitCode: 0).accessibilityLabel == "Command finished successfully")
    #expect(
      TerminalScreenIndicator.commandFinished(exitCode: 2).accessibilityLabel == "Command failed with exit code 2")
    #expect(TerminalScreenIndicator.childExited(exitCode: 9).accessibilityLabel == "Child process exited with code 9")
    #expect(TerminalScreenIndicator.rendererUnhealthy.accessibilityLabel == "Terminal renderer unhealthy")
  }

  @Test("selected screen events are visible only while the app is active")
  func selectedScreenEventsAreVisibleOnlyWhileAppIsActive() {
    #expect(!TerminalScreenAttentionPolicy.shouldApply(.bell, isSelectedScreen: true, appIsActive: true))
    #expect(
      !TerminalScreenAttentionPolicy.shouldApply(
        .commandFinished(exitCode: 1), isSelectedScreen: true, appIsActive: true)
    )
    #expect(
      !TerminalScreenAttentionPolicy.shouldApply(.childExited(exitCode: 9), isSelectedScreen: true, appIsActive: true))
    #expect(TerminalScreenAttentionPolicy.shouldApply(.bell, isSelectedScreen: true, appIsActive: false))
    #expect(TerminalScreenAttentionPolicy.shouldApply(.bell, isSelectedScreen: false, appIsActive: true))
  }

  @Test("semantic terminal events produce OS notification payloads")
  func semanticTerminalEventsProduceNotificationPayloads() {
    #expect(
      TerminalScreenNotificationPolicy.notification(for: .bell, screenTitle: "Build")
        == TerminalNotification(title: "Build", body: "Terminal bell")
    )
    #expect(
      TerminalScreenNotificationPolicy.notification(for: .commandFinished(exitCode: 0), screenTitle: "Build")
        == TerminalNotification(title: "Build", body: "Command finished successfully")
    )
    #expect(
      TerminalScreenNotificationPolicy.notification(for: .commandFinished(exitCode: 2), screenTitle: "Build")
        == TerminalNotification(title: "Build", body: "Command failed with exit code 2")
    )
    #expect(
      TerminalScreenNotificationPolicy.notification(for: .childExited(exitCode: 9), screenTitle: "Build")
        == TerminalNotification(title: "Build", body: "Child process exited with code 9")
    )
    #expect(
      TerminalScreenNotificationPolicy.notification(for: .rendererHealthChanged(healthy: false), screenTitle: "Build")
        == TerminalNotification(title: "Build", body: "Terminal renderer unhealthy")
    )
    #expect(
      TerminalScreenNotificationPolicy.notification(for: .progressChanged(42), screenTitle: "Build")
        == TerminalNotification(title: "Build", body: "Terminal progress 42 percent")
    )
    #expect(TerminalScreenNotificationPolicy.notification(for: .progressChanged(nil), screenTitle: "Build") == nil)
    #expect(
      TerminalScreenNotificationPolicy.notification(for: .rendererHealthChanged(healthy: true), screenTitle: "Build")
        == nil
    )
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
    status.apply(.visibleActivity(nowMilliseconds: 1234))

    #expect(status.lastNotification == TerminalNotification(title: "build", body: "done"))
    #expect(status.hoveredURL == "https://example.com")
    #expect(status.lastColorChange == color)
    #expect(status.configReloadCount == 1)
    #expect(status.configChangeCount == 1)
    #expect(status.search == TerminalSearchState(needle: "warning", total: 3, selected: 2))
    #expect(status.scrollbar == scrollbar)
    #expect(status.lastActivityMilliseconds == 1234)
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

  @Test("live activity debounce stays active through quiet period and clears after")
  func liveActivityDebounceClearsAfterQuietPeriod() {
    let policy = TerminalLiveActivityPolicy(quietPeriodMilliseconds: 400)

    #expect(policy.isActive(lastActivityMilliseconds: nil, nowMilliseconds: 1000) == false)
    #expect(policy.isActive(lastActivityMilliseconds: 1000, nowMilliseconds: 1000))
    #expect(policy.isActive(lastActivityMilliseconds: 1000, nowMilliseconds: 1399))
    #expect(policy.isActive(lastActivityMilliseconds: 1000, nowMilliseconds: 1400) == false)
    #expect(policy.isActive(lastActivityMilliseconds: 1000, nowMilliseconds: 500) == false)
  }

  @Test("live activity respects selected active screen suppression")
  func liveActivityRespectsSelectedActiveScreenSuppression() {
    #expect(
      !TerminalLiveActivityPolicy.shouldShowActivity(
        isActive: true, isSelectedScreen: true, appIsActive: true)
    )
    #expect(
      TerminalLiveActivityPolicy.shouldShowActivity(
        isActive: true, isSelectedScreen: true, appIsActive: false)
    )
    #expect(
      TerminalLiveActivityPolicy.shouldShowActivity(
        isActive: true, isSelectedScreen: false, appIsActive: true)
    )
    #expect(
      !TerminalLiveActivityPolicy.shouldShowActivity(
        isActive: false, isSelectedScreen: false, appIsActive: true)
    )
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
