import Darwin
import Foundation

/// A live AF_UNIX stream socket from a `smoovmux-relay` child.
///
/// Bytes flow in two directions:
///
///   * `fromRelay` — keystrokes from libghostty (relayed via stdin of the
///     child), surfaced as `AsyncStream<Data>` chunks. The stream finishes
///     when the relay closes its write side, when `close()` is called, or on
///     read error.
///   * `write(_:)` — `%output` bytes from tmux to libghostty (relayed via the
///     child's stdout). Writes are blocking and serialized internally so byte
///     order on the wire matches the order of `write` calls.
///
/// `onClose` fires exactly once when the connection ends. Read EOF, write
/// failure, and explicit `close()` all converge here.
public final class PaneConnection: @unchecked Sendable {
  public enum WriteError: Error, Equatable {
    case closed
    case io(errno: Int32)
  }

  public let fromRelay: AsyncStream<Data>
  public let onClose: AsyncStream<Void>

  private let fd: Int32
  private let fromRelayCont: AsyncStream<Data>.Continuation
  private let onCloseCont: AsyncStream<Void>.Continuation
  private let readSource: DispatchSourceRead
  private let writeLock = NSLock()
  private let stateLock = NSLock()
  private var closed = false

  init(fd: Int32) {
    self.fd = fd

    var fromCont: AsyncStream<Data>.Continuation!
    self.fromRelay = AsyncStream<Data>(bufferingPolicy: .unbounded) { fromCont = $0 }
    self.fromRelayCont = fromCont

    var closeCont: AsyncStream<Void>.Continuation!
    self.onClose = AsyncStream<Void>(bufferingPolicy: .unbounded) { closeCont = $0 }
    self.onCloseCont = closeCont

    let readQueue = DispatchQueue(label: "smoovmux.relay.conn.read.\(fd)")
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
    self.readSource = source

    source.setEventHandler { [weak self] in
      self?.handleRead()
    }
    // Cancel handler is the single owner of `close(fd)`. Guarantees the fd is
    // released exactly once even if `close()` and read EOF race.
    source.setCancelHandler {
      Darwin.close(fd)
    }
    source.resume()
  }

  /// Send bytes to the relay (which writes them to the libghostty child's
  /// stdin, i.e. tmux pane `%output`). Blocks until all bytes are flushed to
  /// the kernel or the connection is torn down.
  public func write(_ data: Data) throws {
    writeLock.lock()
    defer { writeLock.unlock() }
    if isClosed() { throw WriteError.closed }
    try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      let total = raw.count
      while offset < total {
        let written = Darwin.write(fd, base.advanced(by: offset), total - offset)
        if written < 0 {
          let code = errno
          if code == EINTR { continue }
          throw WriteError.io(errno: code)
        }
        if written == 0 { throw WriteError.io(errno: EPIPE) }
        offset += written
      }
    }
  }

  /// Tear down the connection. Idempotent. Subsequent reads from `fromRelay`
  /// see the stream end; `onClose` yields once.
  public func close() {
    stateLock.lock()
    if closed {
      stateLock.unlock()
      return
    }
    closed = true
    stateLock.unlock()

    fromRelayCont.finish()
    onCloseCont.yield(())
    onCloseCont.finish()
    readSource.cancel()
  }

  private func isClosed() -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return closed
  }

  private func handleRead() {
    var buffer = [UInt8](repeating: 0, count: 4096)
    let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
      Darwin.read(fd, ptr.baseAddress, ptr.count)
    }
    if bytesRead > 0 {
      fromRelayCont.yield(Data(bytes: buffer, count: bytesRead))
    } else if bytesRead == 0 {
      close()
    } else {
      let code = errno
      if code != EAGAIN && code != EINTR {
        close()
      }
    }
  }
}
