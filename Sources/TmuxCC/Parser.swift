import Foundation

/// A streaming parser for tmux `-CC` control mode output.
///
/// Feed bytes in with `push(_:)` and consume the `Token`s that come back.
/// The parser is a line-oriented state machine that mirrors ghostty's
/// `src/terminal/tmux/control.zig`. It is not thread-safe; the caller is
/// responsible for serialising access (typically via a gateway actor).
public final class Parser {
  public static let defaultMaxBufferBytes = 1 << 20  // 1 MiB

  private enum State {
    case idle
    case notification
    case block
    case broken
  }

  private enum BlockTerminator {
    case end
    case error
  }

  private var state: State = .idle
  private var buffer: [UInt8] = []
  private let maxBufferBytes: Int

  public init(maxBufferBytes: Int = Parser.defaultMaxBufferBytes) {
    self.maxBufferBytes = maxBufferBytes
  }

  /// Feed a single byte. Returns a token when one becomes available.
  public func push(_ byte: UInt8) -> Token? {
    if state == .broken { return nil }

    if buffer.count >= maxBufferBytes {
      breakParser()
      return .exit
    }

    switch state {
    case .broken:
      return nil

    case .idle:
      if byte != 0x25 {  // '%'
        breakParser()
        return .exit
      }
      buffer.removeAll(keepingCapacity: true)
      state = .notification

    case .notification:
      if byte == 0x0a {  // '\n'
        return parseNotification()
      }

    case .block:
      if byte == 0x0a, let token = finishBlockLine() {
        return token
      }
    }

    buffer.append(byte)
    return nil
  }

  /// Called when `\n` arrives in `.block` state. If the just-completed line is
  /// a block terminator (`%end`/`%error`), emits the corresponding token and
  /// resets to `.idle`. Otherwise returns nil so the caller keeps accumulating.
  private func finishBlockLine() -> Token? {
    let lineStart = (buffer.lastIndex(of: 0x0a)).map { $0 + 1 } ?? 0
    let lineBytes = Array(buffer[lineStart...])
    guard let terminator = parseBlockTerminator(lineBytes) else { return nil }

    var payloadEnd = lineStart
    while payloadEnd > 0, buffer[payloadEnd - 1] == 0x0a || buffer[payloadEnd - 1] == 0x0d {
      payloadEnd -= 1
    }
    let payload = Data(buffer[0..<payloadEnd])
    resetToIdle()
    switch terminator {
    case .end: return .blockEnd(data: payload)
    case .error: return .blockError(data: payload)
    }
  }

  /// Feed a chunk of bytes. Returns every token produced, in order.
  public func push(_ bytes: Data) -> [Token] {
    var tokens: [Token] = []
    for byte in bytes {
      if let token = push(byte) { tokens.append(token) }
    }
    return tokens
  }

  /// Feed a chunk of bytes. Overload for byte arrays and test convenience.
  public func push(_ bytes: [UInt8]) -> [Token] {
    var tokens: [Token] = []
    for byte in bytes {
      if let token = push(byte) { tokens.append(token) }
    }
    return tokens
  }

  // MARK: - Notification parsing

  private func parseNotification() -> Token? {
    assert(state == .notification)
    var line = buffer
    if line.last == 0x0d { line.removeLast() }

    let firstSpace = line.firstIndex(of: 0x20) ?? line.endIndex
    let cmdBytes = line[..<firstSpace]
    let cmd = String(bytes: cmdBytes, encoding: .ascii) ?? ""

    switch cmd {
    case "%begin":
      state = .block
      buffer.removeAll(keepingCapacity: true)
      return nil

    case "%output":
      return parseOutput(line: line)

    case "%session-changed":
      return parseSessionChanged(line: line)

    case "%session-renamed":
      return parseSessionRenamed(line: line)

    case "%sessions-changed":
      if line.count == cmdBytes.count {
        resetToIdle()
        return .sessionsChanged
      }
      return unknownAndReset(line: line)

    case "%exit":
      breakParser()
      return .exit

    default:
      return unknownAndReset(line: line)
    }
  }

  private func parseOutput(line: [UInt8]) -> Token? {
    let prefix: [UInt8] = Array("%output %".utf8)
    guard line.count > prefix.count, line.starts(with: prefix) else {
      return unknownAndReset(line: line)
    }
    var idx = prefix.count
    var paneId: UInt = 0
    let idStart = idx
    while idx < line.count, line[idx] >= 0x30, line[idx] <= 0x39 {
      paneId = paneId * 10 + UInt(line[idx] - 0x30)
      idx += 1
    }
    guard idx > idStart, idx < line.count, line[idx] == 0x20 else {
      return unknownAndReset(line: line)
    }
    let payload = Data(line[(idx + 1)...])
    let decoded = decodeTmuxOutput(payload)
    resetToIdle()
    return .output(paneId: paneId, data: decoded)
  }

  private func parseSessionChanged(line: [UInt8]) -> Token? {
    let prefix: [UInt8] = Array("%session-changed $".utf8)
    guard line.count > prefix.count, line.starts(with: prefix) else {
      return unknownAndReset(line: line)
    }
    var idx = prefix.count
    var id: UInt = 0
    let idStart = idx
    while idx < line.count, line[idx] >= 0x30, line[idx] <= 0x39 {
      id = id * 10 + UInt(line[idx] - 0x30)
      idx += 1
    }
    guard idx > idStart, idx < line.count, line[idx] == 0x20 else {
      return unknownAndReset(line: line)
    }
    let nameBytes = Array(line[(idx + 1)...])
    guard let name = String(bytes: nameBytes, encoding: .utf8) else {
      return unknownAndReset(line: line)
    }
    resetToIdle()
    return .sessionChanged(id: id, name: name)
  }

  private func parseSessionRenamed(line: [UInt8]) -> Token? {
    let prefix: [UInt8] = Array("%session-renamed ".utf8)
    guard line.count > prefix.count, line.starts(with: prefix) else {
      return unknownAndReset(line: line)
    }
    let nameBytes = Array(line[prefix.count...])
    guard let name = String(bytes: nameBytes, encoding: .utf8) else {
      return unknownAndReset(line: line)
    }
    resetToIdle()
    return .sessionRenamed(name: name)
  }

  /// A line terminates a `%begin` block only when it exactly matches
  /// `%end|%error <numeric> <numeric> <numeric>`. Payload lines that happen
  /// to start with `%end` or `%error` do not terminate the block. See
  /// ghostty's `parseBlockTerminator` for the same constraint.
  private func parseBlockTerminator(_ lineRaw: [UInt8]) -> BlockTerminator? {
    var line = lineRaw
    if line.last == 0x0d { line.removeLast() }

    let fields = line.split(separator: 0x20, omittingEmptySubsequences: true)
    guard fields.count == 4 else { return nil }

    let cmdStr = String(bytes: fields[0], encoding: .ascii) ?? ""
    let terminator: BlockTerminator
    switch cmdStr {
    case "%end": terminator = .end
    case "%error": terminator = .error
    default: return nil
    }

    for idx in 1...3 {
      guard let str = String(bytes: fields[idx], encoding: .ascii),
        UInt(str) != nil
      else { return nil }
    }

    return terminator
  }

  // MARK: - State helpers

  private func unknownAndReset(line: [UInt8]) -> Token {
    // Notification lines are spec'd as ASCII; if we get non-UTF-8 here the
    // input is malformed anyway, so an empty `.unknown` line is fine.
    let text = String(bytes: line, encoding: .utf8) ?? ""
    resetToIdle()
    return .unknown(line: text)
  }

  private func resetToIdle() {
    state = .idle
    buffer.removeAll(keepingCapacity: true)
  }

  private func breakParser() {
    state = .broken
    buffer = []
  }
}
