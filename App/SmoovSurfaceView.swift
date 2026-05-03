import AppKit
import GhosttyKit
import SmoovLog

/// Minimum viable libghostty surface embedded in an AppKit `NSView`.
///
/// Architecture note: libghostty owns the PTY for this surface. Whatever
/// binary we put in `Config.command` runs as the PTY child, and bytes flow
/// through ghostty's own termio backend, not through Swift. Leaving
/// `Config.command` nil makes libghostty spawn the user's login shell from
/// its config defaults.
@MainActor
final class SmoovSurfaceView: NSView {
  struct Config {
    var command: String? = nil
    var workingDirectory: URL? = nil
    var env: [String: String] = [:]
  }

  /// Current cell grid size reported by libghostty after the last resize.
  private(set) var cellSize: (cols: UInt16, rows: UInt16) = (0, 0)

  /// Called on `setFrameSize` whenever libghostty recomputes the cell grid.
  var onResize: ((UInt16, UInt16) -> Void)?
  var onFocus: (() -> Void)?
  var onFocusChanged: ((Bool) -> Void)?
  var onSplitRequested: ((ghostty_action_split_direction_e) -> Void)?
  var onCloseRequested: (() -> Void)?
  var onCwdChanged: ((URL) -> Void)?

  nonisolated(unsafe) private var surface: ghostty_surface_t?
  private var focused = false

  /// Scratch buffer populated by `insertText` during a `keyDown` call. Non-
  /// nil only while we're inside `interpretKeyEvents` — that's how we avoid
  /// double-delivering: libghostty receives the composed text exactly once,
  /// via `ghostty_surface_key`'s `text` field.
  private var keyTextAccumulator: [String]?

  init(app: GhosttyApp, config: Config) {
    // Non-zero initial frame: the Metal layer bounds must be non-zero when
    // the surface initializes or the renderer has nothing to draw into.
    // Actual size comes in via `setFrameSize` when we get our real layout.
    super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    self.wantsLayer = true
    self.surface = makeSurface(app: app, config: config)
    self.updateTrackingAreas()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }

  deinit {
    if let surface {
      ghostty_surface_free(surface)
    }
  }

  // MARK: - Surface bootstrap

  private func makeSurface(
    app: GhosttyApp,
    config: Config
  ) -> ghostty_surface_t? {
    var cfg = ghostty_surface_config_new()
    cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
    cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
    cfg.platform = ghostty_platform_u(
      macos: ghostty_platform_macos_s(
        nsview: Unmanaged.passUnretained(self).toOpaque()
      )
    )
    cfg.scale_factor = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)
    cfg.font_size = 0
    cfg.wait_after_command = false
    cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

    // C-string lifetimes must extend across ghostty_surface_new, which copies
    // what it needs before returning. Nest `withCString` so every pointer is
    // valid at the call site.
    let envKeys = Array(config.env.keys)
    let envValues = envKeys.map { config.env[$0] ?? "" }

    func withCStrings<T>(
      _ strings: [String],
      _ body: ([UnsafePointer<CChar>?]) -> T
    ) -> T {
      if strings.isEmpty { return body([]) }
      func step(_ index: Int, _ acc: [UnsafePointer<CChar>?]) -> T {
        if index == strings.count { return body(acc) }
        return strings[index].withCString { ptr in
          var next = acc
          next.append(ptr)
          return step(index + 1, next)
        }
      }
      return step(0, [])
    }

    func withOptionalCString<T>(
      _ string: String?,
      _ body: (UnsafePointer<CChar>?) -> T
    ) -> T {
      guard let string else { return body(nil) }
      return string.withCString(body)
    }

    let command = config.command
    let workingDirectory = config.workingDirectory?.path
    return withOptionalCString(command) { cCommand -> ghostty_surface_t? in
      cfg.command = cCommand
      return withOptionalCString(workingDirectory) { cWorkingDirectory in
        cfg.working_directory = cWorkingDirectory
        return withCStrings(envKeys) { keyPtrs in
          withCStrings(envValues) { valuePtrs in
            var entries = [ghostty_env_var_s]()
            entries.reserveCapacity(envKeys.count)
            for i in 0..<envKeys.count {
              entries.append(ghostty_env_var_s(key: keyPtrs[i], value: valuePtrs[i]))
            }
            return entries.withUnsafeMutableBufferPointer { buffer in
              cfg.env_vars = buffer.baseAddress
              cfg.env_var_count = envKeys.count
              guard let s = ghostty_surface_new(app.cValue, &cfg) else {
                SmoovLog.error("ghostty_surface_new returned nil")
                return nil
              }
              return s
            }
          }
        }
      }
    }
  }

  // MARK: - Pane actions

  func splitRight() {
    onSplitRequested?(GHOSTTY_SPLIT_DIRECTION_RIGHT)
  }

  func splitDown() {
    onSplitRequested?(GHOSTTY_SPLIT_DIRECTION_DOWN)
  }

  func requestClosePane() {
    guard let surface else { return }
    ghostty_surface_request_close(surface)
  }

  func handleGhosttySplitAction(_ direction: ghostty_action_split_direction_e) {
    onSplitRequested?(direction)
  }

  func handleGhosttyCloseAction() {
    onCloseRequested?()
  }

  func handleGhosttyPwdAction(_ pwd: String) {
    guard !pwd.isEmpty else { return }
    onCwdChanged?(URL(fileURLWithPath: pwd))
  }

  // MARK: - NSView overrides

  override var acceptsFirstResponder: Bool { true }

  override func becomeFirstResponder() -> Bool {
    let ok = super.becomeFirstResponder()
    if ok, let surface {
      focused = true
      onFocus?()
      onFocusChanged?(true)
      ghostty_surface_set_focus(surface, true)
    }
    return ok
  }

  override func resignFirstResponder() -> Bool {
    let ok = super.resignFirstResponder()
    if ok, let surface {
      focused = false
      onFocusChanged?(false)
      ghostty_surface_set_focus(surface, false)
    }
    return ok
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    guard let surface else { return }
    let backing = convertToBacking(newSize)
    ghostty_surface_set_size(surface, UInt32(backing.width), UInt32(backing.height))
    let size = ghostty_surface_size(surface)
    cellSize = (size.columns, size.rows)
    onResize?(size.columns, size.rows)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let surface, let window else { return }
    let scale = window.backingScaleFactor
    ghostty_surface_set_content_scale(surface, scale, scale)
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    guard let surface, let window else { return }
    let scale = window.backingScaleFactor
    ghostty_surface_set_content_scale(surface, scale, scale)
  }

  override func updateTrackingAreas() {
    for area in trackingAreas { removeTrackingArea(area) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
  }

  // MARK: - Mouse

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    sendMousePos(event)
    sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
  }

  override func mouseUp(with event: NSEvent) {
    sendMousePos(event)
    sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    if let surface {
      ghostty_surface_mouse_pressure(surface, 0, 0)
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    sendMousePos(event)
    guard sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT) else {
      super.rightMouseDown(with: event)
      return
    }
  }

  override func rightMouseUp(with event: NSEvent) {
    sendMousePos(event)
    guard sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT) else {
      super.rightMouseUp(with: event)
      return
    }
  }

  override func otherMouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    sendMousePos(event)
    sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: mouseButton(for: event.buttonNumber))
  }

  override func otherMouseUp(with event: NSEvent) {
    sendMousePos(event)
    sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: mouseButton(for: event.buttonNumber))
  }

  override func mouseMoved(with event: NSEvent) {
    sendMousePos(event)
  }

  override func mouseDragged(with event: NSEvent) {
    sendMousePos(event)
  }

  override func rightMouseDragged(with event: NSEvent) {
    sendMousePos(event)
  }

  override func otherMouseDragged(with event: NSEvent) {
    sendMousePos(event)
  }

  override func mouseEntered(with event: NSEvent) {
    sendMousePos(event)
  }

  override func mouseExited(with event: NSEvent) {
    guard let surface else { return }
    ghostty_surface_mouse_pos(surface, -1, -1, NSEventGhostty.mods(event.modifierFlags))
  }

  override func scrollWheel(with event: NSEvent) {
    guard let surface else { return }
    var deltaX = event.scrollingDeltaX
    var deltaY = event.scrollingDeltaY
    let precision = event.hasPreciseScrollingDeltas
    if precision {
      deltaX *= 2
      deltaY *= 2
    }
    ghostty_surface_mouse_scroll(surface, deltaX, deltaY, scrollMods(for: event, precision: precision))
  }

  override func pressureChange(with event: NSEvent) {
    guard let surface else { return }
    ghostty_surface_mouse_pressure(surface, UInt32(event.stage), Double(event.pressure))
  }

  private func sendMousePos(_ event: NSEvent) {
    guard let surface else { return }
    let pos = convert(event.locationInWindow, from: nil)
    ghostty_surface_mouse_pos(
      surface,
      pos.x,
      bounds.height - pos.y,
      NSEventGhostty.mods(event.modifierFlags)
    )
  }

  @discardableResult
  private func sendMouseButton(
    _ event: NSEvent,
    state: ghostty_input_mouse_state_e,
    button: ghostty_input_mouse_button_e
  ) -> Bool {
    guard let surface else { return false }
    return ghostty_surface_mouse_button(surface, state, button, NSEventGhostty.mods(event.modifierFlags))
  }

  private func mouseButton(for buttonNumber: Int) -> ghostty_input_mouse_button_e {
    switch buttonNumber {
    case 0:
      return GHOSTTY_MOUSE_LEFT
    case 1:
      return GHOSTTY_MOUSE_RIGHT
    case 2:
      return GHOSTTY_MOUSE_MIDDLE
    case 3:
      return GHOSTTY_MOUSE_EIGHT
    case 4:
      return GHOSTTY_MOUSE_NINE
    case 5:
      return GHOSTTY_MOUSE_SIX
    case 6:
      return GHOSTTY_MOUSE_SEVEN
    case 7:
      return GHOSTTY_MOUSE_FOUR
    case 8:
      return GHOSTTY_MOUSE_FIVE
    case 9:
      return GHOSTTY_MOUSE_TEN
    case 10:
      return GHOSTTY_MOUSE_ELEVEN
    default:
      return GHOSTTY_MOUSE_UNKNOWN
    }
  }

  private func scrollMods(for event: NSEvent, precision: Bool) -> ghostty_input_scroll_mods_t {
    var value: Int32 = precision ? 1 : 0
    value |= Int32(mouseMomentum(for: event.momentumPhase).rawValue) << 1
    return ghostty_input_scroll_mods_t(value)
  }

  private func mouseMomentum(for phase: NSEvent.Phase) -> ghostty_input_mouse_momentum_e {
    switch phase {
    case .began:
      return GHOSTTY_MOUSE_MOMENTUM_BEGAN
    case .stationary:
      return GHOSTTY_MOUSE_MOMENTUM_STATIONARY
    case .changed:
      return GHOSTTY_MOUSE_MOMENTUM_CHANGED
    case .ended:
      return GHOSTTY_MOUSE_MOMENTUM_ENDED
    case .cancelled:
      return GHOSTTY_MOUSE_MOMENTUM_CANCELLED
    case .mayBegin:
      return GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
    default:
      return GHOSTTY_MOUSE_MOMENTUM_NONE
    }
  }

  // MARK: - Keyboard

  override func keyDown(with event: NSEvent) {
    guard let surface else { return }
    let action: ghostty_input_action_e =
      event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

    // Run the event through AppKit's input stack so dead keys and option
    // combos get composed. We collect whatever `insertText` produces into
    // the accumulator instead of delivering it directly — otherwise
    // libghostty would see the text twice (once from `ghostty_surface_key`
    // below, once from `ghostty_surface_text` in `insertText`).
    keyTextAccumulator = []
    interpretKeyEvents([event])
    let composed = keyTextAccumulator?.joined()
    keyTextAccumulator = nil

    let text = (composed?.isEmpty == false) ? composed : NSEventGhostty.characters(event)
    sendKey(surface: surface, event: event, action: action, text: text)
  }

  override func keyUp(with event: NSEvent) {
    guard let surface else { return }
    sendKey(surface: surface, event: event, action: GHOSTTY_ACTION_RELEASE, text: nil)
  }

  override func flagsChanged(with event: NSEvent) {
    guard let surface else { return }
    // Which bit changed? Map the keyCode back to a modifier mask so we know
    // whether this is a press or release.
    let mask: UInt32
    switch event.keyCode {
    case 0x39: mask = GHOSTTY_MODS_CAPS.rawValue
    case 0x38, 0x3c: mask = GHOSTTY_MODS_SHIFT.rawValue
    case 0x3b, 0x3e: mask = GHOSTTY_MODS_CTRL.rawValue
    case 0x3a, 0x3d: mask = GHOSTTY_MODS_ALT.rawValue
    case 0x37, 0x36: mask = GHOSTTY_MODS_SUPER.rawValue
    default: return
    }
    let currentMods = NSEventGhostty.mods(event.modifierFlags)
    let action: ghostty_input_action_e =
      (currentMods.rawValue & mask) != 0 ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
    sendKey(surface: surface, event: event, action: action, text: nil)
  }

  private func sendKey(
    surface: ghostty_surface_t,
    event: NSEvent,
    action: ghostty_input_action_e,
    text: String?
  ) {
    var keyEv = NSEventGhostty.keyEvent(event, action: action)
    // Only attach text for printable characters. Libghostty encodes control
    // characters itself from the keycode + mods, so passing "\r" as text for
    // ctrl+enter (for instance) produces wrong output.
    if let text, !text.isEmpty, let first = text.utf8.first, first >= 0x20 {
      text.withCString { ptr in
        keyEv.text = ptr
        _ = ghostty_surface_key(surface, keyEv)
      }
    } else {
      _ = ghostty_surface_key(surface, keyEv)
    }
  }

  override func doCommand(by selector: Selector) {
    // Intentionally empty. keyDown already fired ghostty_surface_key; we
    // just swallow the selector here to avoid NSBeep.
  }

  // MARK: - Clipboard

  @objc func copy(_ sender: Any?) {
    guard let selectedText else { return }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(selectedText, forType: .string)
  }

  @objc func cut(_ sender: Any?) {
    copy(sender)
  }

  @objc func paste(_ sender: Any?) {
    guard
      let surface,
      let text = NSPasteboard.general.string(forType: .string),
      !text.isEmpty
    else { return }

    text.withCString { ptr in
      ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
    }
  }

  override func selectAll(_ sender: Any?) {
    // Terminal select-all needs scrollback-aware support from libghostty.
    // Keep the selector present for menu validation, but disabled for now.
  }

  func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(copy(_:)), #selector(cut(_:)):
      return selectedText != nil
    case #selector(paste(_:)):
      return NSPasteboard.general.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue])
    case #selector(selectAll(_:)):
      return false
    default:
      return true
    }
  }

  private var selectedText: String? {
    guard let surface, ghostty_surface_has_selection(surface) else { return nil }

    var text = ghostty_text_s(
      tl_px_x: 0,
      tl_px_y: 0,
      offset_start: 0,
      offset_len: 0,
      text: nil,
      text_len: 0
    )
    guard ghostty_surface_read_selection(surface, &text) else { return nil }
    defer { ghostty_surface_free_text(surface, &text) }
    guard let pointer = text.text, text.text_len > 0 else { return nil }

    let data = Data(bytes: pointer, count: Int(text.text_len))
    return String(data: data, encoding: .utf8)
  }
}

// MARK: - NSTextInputClient (text path)
//
// We implement the minimum needed to route composed characters (dead keys,
// option-combos) into libghostty. IME / marked-text is out of scope for
// M1 — all marked-text APIs return empty / nil. The conformance is
// `@MainActor` isolated because every method touches the surface pointer,
// which libghostty expects to be accessed from the main thread only.
extension SmoovSurfaceView: @MainActor NSTextInputClient {
  func insertText(_ string: Any, replacementRange: NSRange) {
    let text: String
    switch string {
    case let s as String: text = s
    case let s as NSAttributedString: text = s.string
    default: return
    }
    guard !text.isEmpty else { return }

    // If we're inside a `keyDown` call, stash the composed text so the
    // outer `keyDown` delivers it in one shot via `ghostty_surface_key`.
    // Direct `ghostty_surface_text` here would double the character.
    if keyTextAccumulator != nil {
      keyTextAccumulator?.append(text)
      return
    }

    // External insertion (e.g., menu, drag-drop) — no outer keyDown.
    guard let surface else { return }
    text.withCString { ptr in
      ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
    }
  }

  func hasMarkedText() -> Bool { false }
  func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
  func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
  func unmarkText() {}
  func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
  func attributedSubstring(
    forProposedRange range: NSRange,
    actualRange: NSRangePointer?
  ) -> NSAttributedString? { nil }
  func characterIndex(for point: NSPoint) -> Int { NSNotFound }
  func firstRect(
    forCharacterRange range: NSRange,
    actualRange: NSRangePointer?
  ) -> NSRect {
    NSRect(x: 0, y: 0, width: 0, height: 0)
  }
}
