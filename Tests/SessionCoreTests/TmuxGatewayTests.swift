import Foundation
import Testing

@testable import SessionCore

@Suite("TmuxGateway")
struct TmuxGatewayTests {
  /// Builds a gateway wired to two streams the test owns: `inputCont` to
  /// simulate bytes coming back from tmux, `outputs` to observe bytes the
  /// gateway writes. The output closure yields synchronously, so awaiting the
  /// next `outputs` value is a deterministic barrier meaning "the gateway has
  /// already enqueued the send's continuation" — removing the need for sleeps.
  private func makeGateway() -> (
    gateway: TmuxGateway,
    inputCont: AsyncStream<Data>.Continuation,
    outputs: AsyncStream<Data>
  ) {
    var inputContVar: AsyncStream<Data>.Continuation!
    let input = AsyncStream<Data>(bufferingPolicy: .unbounded) { inputContVar = $0 }
    var outputContVar: AsyncStream<Data>.Continuation!
    let outputs = AsyncStream<Data>(bufferingPolicy: .unbounded) { outputContVar = $0 }
    let outputCont = outputContVar!
    let gateway = TmuxGateway(input: input) { data in outputCont.yield(data) }
    return (gateway, inputContVar, outputs)
  }

  // MARK: - Commands

  @Test func sendReturnsResponseLines() async throws {
    let (gateway, inputCont, outputs) = makeGateway()
    let drain = Task { await gateway.start() }

    async let result = gateway.send("list-panes")

    var outIter = outputs.makeAsyncIterator()
    let written = await outIter.next()
    #expect(written == Data("list-panes\n".utf8))

    inputCont.yield(Data("%begin 1 1 1\nhello\nworld\n%end 1 1 1\n".utf8))
    let lines = try await result
    #expect(lines == ["hello", "world"])

    inputCont.finish()
    await drain.value
  }

  @Test func emptyResponseIsEmptyArray() async throws {
    let (gateway, inputCont, outputs) = makeGateway()
    let drain = Task { await gateway.start() }

    async let result = gateway.send("noop")
    var outIter = outputs.makeAsyncIterator()
    _ = await outIter.next()

    inputCont.yield(Data("%begin 1 1 1\n%end 1 1 1\n".utf8))
    let lines = try await result
    #expect(lines.isEmpty)

    inputCont.finish()
    await drain.value
  }

  @Test func errorResponseThrowsCommandFailed() async throws {
    let (gateway, inputCont, outputs) = makeGateway()
    let drain = Task { await gateway.start() }

    let task = Task { try await gateway.send("bogus") }
    var outIter = outputs.makeAsyncIterator()
    _ = await outIter.next()

    inputCont.yield(Data("%begin 1 1 1\nunknown command\n%error 1 1 1\n".utf8))
    await #expect(throws: TmuxGateway.GatewayError.commandFailed("unknown command")) {
      _ = try await task.value
    }

    inputCont.finish()
    await drain.value
  }

  @Test func concurrentSendsAreFIFOMatched() async throws {
    let (gateway, inputCont, outputs) = makeGateway()
    let drain = Task { await gateway.start() }

    // Sequentially start each send and wait for its write to drain before
    // kicking off the next. This pins the actor-enqueue order so the first
    // %end response matches `firstTask` and the second matches `secondTask`.
    var outIter = outputs.makeAsyncIterator()
    let firstTask = Task { try await gateway.send("cmd-1") }
    #expect(await outIter.next() == Data("cmd-1\n".utf8))
    let secondTask = Task { try await gateway.send("cmd-2") }
    #expect(await outIter.next() == Data("cmd-2\n".utf8))

    inputCont.yield(Data("%begin 1 1 1\nA\n%end 1 1 1\n%begin 1 2 1\nB\n%end 1 2 1\n".utf8))
    #expect(try await firstTask.value == ["A"])
    #expect(try await secondTask.value == ["B"])

    inputCont.finish()
    await drain.value
  }

  // MARK: - Pane output routing

  @Test func outputIsRoutedToSubscribedPane() async throws {
    let (gateway, inputCont, _) = makeGateway()
    let drain = Task { await gateway.start() }

    let stream = await gateway.subscribe(paneId: 1)
    inputCont.yield(Data("%output %1 hi\n".utf8))
    inputCont.yield(Data("%output %2 ignored\n".utf8))
    inputCont.yield(Data("%output %1 bye\n".utf8))

    var iter = stream.makeAsyncIterator()
    #expect(await iter.next() == Data("hi".utf8))
    #expect(await iter.next() == Data("bye".utf8))

    inputCont.finish()
    await drain.value
  }

  @Test func unsubscribeStopsRouting() async throws {
    let (gateway, inputCont, _) = makeGateway()
    let drain = Task { await gateway.start() }

    let stream = await gateway.subscribe(paneId: 1)
    inputCont.yield(Data("%output %1 first\n".utf8))
    var iter = stream.makeAsyncIterator()
    #expect(await iter.next() == Data("first".utf8))

    await gateway.unsubscribe(paneId: 1)
    // After unsubscribe, the stream should finish; iterator returns nil.
    #expect(await iter.next() == nil)

    inputCont.finish()
    await drain.value
  }

  // MARK: - State transitions

  @Test func sessionChangedPublishesAttached() async throws {
    let (gateway, inputCont, _) = makeGateway()
    let drain = Task { await gateway.start() }

    var states = gateway.stateStream.makeAsyncIterator()
    #expect(await states.next() == .connecting)

    inputCont.yield(Data("%session-changed $7 work\n".utf8))
    #expect(await states.next() == .attached(sessionId: 7, name: "work"))

    inputCont.finish()
    #expect(await states.next() == .detached(reason: nil))
    await drain.value
  }

  @Test func exitDetachesAndFailsPendingSend() async throws {
    let (gateway, inputCont, outputs) = makeGateway()
    let drain = Task { await gateway.start() }

    let task = Task { try await gateway.send("hang") }
    var outIter = outputs.makeAsyncIterator()
    _ = await outIter.next()

    inputCont.yield(Data("%exit\n".utf8))
    await #expect(throws: TmuxGateway.GatewayError.detached(reason: "tmux exit")) {
      _ = try await task.value
    }

    inputCont.finish()
    await drain.value
  }

  @Test func sendAfterDetachThrowsImmediately() async throws {
    let (gateway, inputCont, _) = makeGateway()
    let drain = Task { await gateway.start() }

    inputCont.yield(Data("%exit\n".utf8))
    inputCont.finish()
    await drain.value

    await #expect(throws: TmuxGateway.GatewayError.detached(reason: "tmux exit")) {
      _ = try await gateway.send("too-late")
    }
  }

  // MARK: - Fixture

  @Test func fixtureOnePaneAttach() async throws {
    let url = try #require(
      Bundle.module.url(
        forResource: "one-pane-attach", withExtension: "bytes", subdirectory: "Fixtures")
    )
    let bytes = try Data(contentsOf: url)

    let (gateway, inputCont, _) = makeGateway()
    let drain = Task { await gateway.start() }

    let paneStream = await gateway.subscribe(paneId: 1)
    var states = gateway.stateStream.makeAsyncIterator()
    #expect(await states.next() == .connecting)

    inputCont.yield(bytes)
    inputCont.finish()

    #expect(await states.next() == .attached(sessionId: 0, name: "main"))
    #expect(await states.next() == .detached(reason: "tmux exit"))

    var paneIter = paneStream.makeAsyncIterator()
    #expect(await paneIter.next() == Data("hello world".utf8))
    #expect(await paneIter.next() == nil)

    await drain.value
  }
}
