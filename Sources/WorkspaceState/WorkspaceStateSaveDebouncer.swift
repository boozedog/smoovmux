import Foundation

public actor WorkspaceStateSaveDebouncer {
  public typealias Save = @Sendable (WorkspaceState) async -> Void

  private let delay: Duration
  private let save: Save
  private var pendingState: WorkspaceState?
  private var pendingTask: Task<Void, Never>?

  public init(delay: Duration, save: @escaping Save) {
    self.delay = delay
    self.save = save
  }

  deinit {
    pendingTask?.cancel()
  }

  public func schedule(_ state: WorkspaceState) {
    pendingState = state
    pendingTask?.cancel()
    pendingTask = Task { [delay] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await flushNow()
    }
  }

  public func flushNow() async {
    pendingTask?.cancel()
    pendingTask = nil
    guard let state = pendingState else { return }
    pendingState = nil
    await save(state)
  }
}
