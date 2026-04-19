import Foundation
import SmoovLog
import TmuxCC

/// Protocol-layer bridge between a `TmuxCC.Parser` and the rest of the app.
///
/// A single tmux `-CC` control connection is modelled as one gateway. Bytes
/// from the tmux-side PTY are pushed in via an `AsyncStream<Data>` and parser
/// tokens are translated into three externally observable effects:
///
///   1. Command round-trips via `send(_:)`. tmux guarantees one response block
///      at a time and answers commands in the order they were written, so the
///      gateway maintains a FIFO of pending continuations: each `%end` resumes
///      the oldest pending `send`, each `%error` fails it.
///   2. Pane byte routing via `subscribe(paneId:)`. `%output` tokens are
///      forwarded to per-pane `AsyncStream<Data>` sinks.
///   3. Connection lifecycle via `stateStream`. `%session-changed` flips the
///      state from `.connecting` to `.attached`; `%exit` (or the input stream
///      closing) flips it to `.detached` and drains pending work.
///
/// The type is an `actor` because parser drains happen on the `start()` task
/// while `send` / `subscribe` are called from arbitrary callers. Inside the
/// actor, the output closure is invoked synchronously so byte ordering on the
/// PTY matches the order of `send` invocations.
public actor TmuxGateway {
  public enum State: Sendable, Equatable {
    case connecting
    case attached(sessionId: UInt, name: String)
    case detached(reason: String?)
  }

  public enum GatewayError: Error, Equatable {
    case commandFailed(String)
    case detached(reason: String?)
  }

  private let input: AsyncStream<Data>
  private let output: @Sendable (Data) -> Void
  private let parser = Parser()

  private var pendingCommands: [CheckedContinuation<[String], Error>] = []
  private var paneSinks: [UInt: AsyncStream<Data>.Continuation] = [:]
  private var state: State = .connecting
  private var started = false

  private let stateContinuation: AsyncStream<State>.Continuation
  nonisolated public let stateStream: AsyncStream<State>

  public init(input: AsyncStream<Data>, output: @escaping @Sendable (Data) -> Void) {
    self.input = input
    self.output = output
    var cont: AsyncStream<State>.Continuation!
    self.stateStream = AsyncStream<State>(bufferingPolicy: .unbounded) { cont = $0 }
    self.stateContinuation = cont
    self.stateContinuation.yield(.connecting)
  }

  /// Drain the input stream until it ends or `%exit` arrives. Call once.
  public func start() async {
    guard !started else { return }
    started = true

    for await chunk in input {
      let tokens = parser.push(chunk)
      for token in tokens {
        handle(token)
        if case .detached = state { break }
      }
      if case .detached = state { break }
    }
    transitionToDetached(reason: state == .connecting ? "input closed" : nil)
  }

  /// Send a command and wait for its response block. Throws `.commandFailed`
  /// on `%error`, `.detached` if the connection drops before the response.
  public func send(_ command: String) async throws -> [String] {
    if case .detached(let reason) = state {
      throw GatewayError.detached(reason: reason)
    }
    return try await withCheckedThrowingContinuation { cont in
      pendingCommands.append(cont)
      var bytes = Data(command.utf8)
      bytes.append(0x0a)
      output(bytes)
    }
  }

  /// Stream pane bytes for `paneId`. A second subscribe replaces the first.
  public func subscribe(paneId: UInt) -> AsyncStream<Data> {
    if let existing = paneSinks.removeValue(forKey: paneId) {
      existing.finish()
    }
    var cont: AsyncStream<Data>.Continuation!
    let stream = AsyncStream<Data>(bufferingPolicy: .unbounded) { cont = $0 }
    paneSinks[paneId] = cont
    return stream
  }

  public func unsubscribe(paneId: UInt) {
    paneSinks.removeValue(forKey: paneId)?.finish()
  }

  // MARK: - Private

  private func handle(_ token: Token) {
    switch token {
    case .blockEnd(let data):
      guard !pendingCommands.isEmpty else {
        SmoovLog.warn("tmux %end with no pending command")
        return
      }
      pendingCommands.removeFirst().resume(returning: splitLines(data))

    case .blockError(let data):
      guard !pendingCommands.isEmpty else {
        SmoovLog.warn("tmux %error with no pending command")
        return
      }
      let message = String(data: data, encoding: .utf8) ?? ""
      pendingCommands.removeFirst().resume(throwing: GatewayError.commandFailed(message))

    case .output(let paneId, let data):
      paneSinks[paneId]?.yield(data)

    case .sessionChanged(let id, let name):
      let next = State.attached(sessionId: id, name: name)
      if state != next {
        state = next
        stateContinuation.yield(next)
      }

    case .sessionRenamed, .sessionsChanged:
      break

    case .exit:
      transitionToDetached(reason: "tmux exit")

    case .unknown(let line):
      SmoovLog.warn("unhandled tmux -CC notification: \(line)")
    }
  }

  private func splitLines(_ data: Data) -> [String] {
    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
      return []
    }
    return text.components(separatedBy: "\n")
  }

  private func transitionToDetached(reason: String?) {
    if case .detached = state { return }
    let next = State.detached(reason: reason)
    state = next
    stateContinuation.yield(next)
    stateContinuation.finish()

    let pending = pendingCommands
    pendingCommands.removeAll()
    for cont in pending {
      cont.resume(throwing: GatewayError.detached(reason: reason))
    }

    let sinks = paneSinks
    paneSinks.removeAll()
    for (_, sink) in sinks {
      sink.finish()
    }
  }
}
