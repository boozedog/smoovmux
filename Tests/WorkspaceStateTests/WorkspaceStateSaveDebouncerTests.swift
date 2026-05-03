import Foundation
import Testing
import WorkspaceState

@Suite("Workspace state save debouncer")
struct WorkspaceStateSaveDebouncerTests {
  @Test("rapid saves are coalesced and the latest state is flushed")
  func rapidSavesAreCoalesced() async throws {
    let first = WorkspaceState(
      tabs: [], selectedTabId: nil, windowFrame: WorkspaceWindowFrame(x: 1, y: 2, width: 3, height: 4))
    let second = WorkspaceState(
      tabs: [], selectedTabId: nil, windowFrame: WorkspaceWindowFrame(x: 5, y: 6, width: 7, height: 8))
    let recorder = SaveRecorder()
    let debouncer = WorkspaceStateSaveDebouncer(delay: .milliseconds(40)) { state in
      await recorder.record(state)
    }

    await debouncer.schedule(first)
    await debouncer.schedule(second)
    try await Task.sleep(for: .milliseconds(120))

    let saved = await recorder.saved
    #expect(saved == [second])
  }

  @Test("flush now writes pending state immediately")
  func flushNowWritesPendingStateImmediately() async throws {
    let state = WorkspaceState(
      tabs: [], selectedTabId: nil, windowFrame: WorkspaceWindowFrame(x: 1, y: 2, width: 3, height: 4))
    let recorder = SaveRecorder()
    let debouncer = WorkspaceStateSaveDebouncer(delay: .seconds(60)) { state in
      await recorder.record(state)
    }

    await debouncer.schedule(state)
    await debouncer.flushNow()

    let saved = await recorder.saved
    #expect(saved == [state])
  }
}

private actor SaveRecorder {
  private(set) var saved: [WorkspaceState] = []

  func record(_ state: WorkspaceState) {
    saved.append(state)
  }
}
