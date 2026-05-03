import Foundation

public actor WorkspaceStateSaveDebouncer<State: Sendable> {
  public typealias Save = @Sendable (State) async -> Void

  private let delay: Duration
  private let save: Save
  private var pendingState: State?
  private var pendingTask: Task<Void, Never>?

  public init(delay: Duration, save: @escaping Save) {
    self.delay = delay
    self.save = save
  }

  deinit {
    pendingTask?.cancel()
  }

  public func schedule(_ state: State) {
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
