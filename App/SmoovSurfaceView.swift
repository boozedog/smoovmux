import AppKit
import GhosttyKit
import SessionCore
import SmoovLog
@preconcurrency import UserNotifications
import WorkspaceSidebar

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
    var command: String?
    var workingDirectory: URL?
    var env: [String: String] = [:]
  }

  /// Current cell grid size reported by libghostty after the last resize.
  private(set) var cellSize: (cols: UInt16, rows: UInt16) = (0, 0)

  /// Called on `setFrameSize` whenever libghostty recomputes the cell grid.
  var onResize: ((UInt16, UInt16) -> Void)?
  var onFocus: (() -> Void)?
  var onFocusChanged: ((Bool) -> Void)?
  var onTitleChanged: ((String) -> Void)?
  var onBell: (() -> Void)?
  var onProgressChanged: ((Int?) -> Void)?
  var onCommandFinished: ((Int16?) -> Void)?
  var onChildExited: ((UInt32) -> Void)?
  var onRendererHealthChanged: ((Bool) -> Void)?
  var onDesktopNotification: ((TerminalNotification) -> Void)?
  var onMouseOverLink: ((String?) -> Void)?
  var onColorChanged: ((TerminalColorChange) -> Void)?
  var onConfigReloaded: ((Bool) -> Void)?
  var onConfigChanged: (() -> Void)?
  var onSearchStarted: ((String?) -> Void)?
  var onSearchEnded: (() -> Void)?
  var onSearchTotal: ((Int?) -> Void)?
  var onSearchSelected: ((Int?) -> Void)?
  var onScrollbarChanged: ((TerminalScrollbar) -> Void)?
  var onSplitRequested: ((ghostty_action_split_direction_e) -> Void)?
  var onCloseRequested: (() -> Void)?
  var onCwdChanged: ((URL) -> Void)?

  private let app: GhosttyApp
  private let imageStore = TerminalImageStore()
  nonisolated(unsafe) private var surface: ghostty_surface_t?
  private var focused = false
  private var hoveredURL: URL?
  private var dropHighlightVisible = false

  /// Scratch buffer populated by `insertText` during a `keyDown` call. Non-
  /// nil only while we're inside `interpretKeyEvents` — that's how we avoid
  /// double-delivering: libghostty receives the composed text exactly once,
  /// via `ghostty_surface_key`'s `text` field.
  private var keyTextAccumulator: [String]?

  init(app: GhosttyApp, config: Config) {
    // Non-zero initial frame: the Metal layer bounds must be non-zero when
    // the surface initializes or the renderer has nothing to draw into.
    // Actual size comes in via `setFrameSize` when we get our real layout.
    self.app = app
    super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    self.wantsLayer = true
    self.surface = makeSurface(app: app, config: config)
    registerForDraggedTypes(Self.terminalDragTypes)
    self.updateTrackingAreas()
  }

  @available(*, unavailable, message: "Use init(app:config:) instead")
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
            for index in 0..<envKeys.count {
              entries.append(ghostty_env_var_s(key: keyPtrs[index], value: valuePtrs[index]))
            }
            return entries.withUnsafeMutableBufferPointer { buffer in
              cfg.env_vars = buffer.baseAddress
              cfg.env_var_count = envKeys.count
              guard let newSurface = ghostty_surface_new(app.cValue, &cfg) else {
                SmoovLog.error("ghostty_surface_new returned nil")
                return nil
              }
              return newSurface
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

  func setTerminalFocused(_ isFocused: Bool) {
    focused = isFocused
    guard let surface else { return }
    ghostty_surface_set_focus(surface, isFocused)
  }

  func handleGhosttyCloseAction() {
    onCloseRequested?()
  }

  func handleGhosttyPwdAction(_ pwd: String) {
    guard !pwd.isEmpty else { return }
    onCwdChanged?(URL(fileURLWithPath: pwd))
  }

  func handleGhosttySetTitleAction(_ title: String) {
    onTitleChanged?(title)
  }

  func handleGhosttyBellAction() {
    onBell?()
  }

  func handleGhosttyProgressAction(_ progress: Int?) {
    onProgressChanged?(progress)
  }

  func handleGhosttyCommandFinishedAction(exitCode: Int16?) {
    onCommandFinished?(exitCode)
  }

  func handleGhosttyChildExitedAction(exitCode: UInt32) {
    onChildExited?(exitCode)
  }

  func handleGhosttyRendererHealthAction(healthy: Bool) {
    onRendererHealthChanged?(healthy)
  }

  func handleGhosttyDesktopNotificationAction(title: String, body: String) {
    let notification = TerminalNotification(title: title, body: body)
    onDesktopNotification?(notification)
    postUserNotification(notification)
  }

  func handleGhosttyMouseShapeAction(_ shape: ghostty_action_mouse_shape_e) {
    cursor(for: shape).set()
  }

  func handleGhosttyMouseVisibilityAction(_ visibility: ghostty_action_mouse_visibility_e) {
    switch visibility {
    case GHOSTTY_MOUSE_VISIBLE:
      NSCursor.setHiddenUntilMouseMoves(false)
    case GHOSTTY_MOUSE_HIDDEN:
      NSCursor.setHiddenUntilMouseMoves(true)
    default:
      break
    }
  }

  func handleGhosttyMouseOverLinkAction(_ url: URL?) {
    hoveredURL = url
    onMouseOverLink?(url?.absoluteString)
    if url == nil {
      NSCursor.arrow.set()
    } else {
      NSCursor.pointingHand.set()
    }
  }

  func handleGhosttyColorChangeAction(_ colorChange: TerminalColorChange) {
    onColorChanged?(colorChange)
  }

  func handleGhosttyReloadConfigAction(soft: Bool) {
    app.reloadConfig(surface: surface, soft: soft)
    onConfigReloaded?(soft)
  }

  func handleGhosttyConfigChangeAction() {
    onConfigChanged?()
  }

  func handleGhosttyStartSearchAction(needle: String?) {
    onSearchStarted?(needle)
  }

  func handleGhosttyEndSearchAction() {
    onSearchEnded?()
  }

  func handleGhosttySearchTotalAction(_ total: Int?) {
    onSearchTotal?(total)
  }

  func handleGhosttySearchSelectedAction(_ selected: Int?) {
    onSearchSelected?(selected)
  }

  func handleGhosttyScrollbarAction(_ scrollbar: TerminalScrollbar) {
    onScrollbarChanged?(scrollbar)
  }

  func handleGhosttyOpenURLAction(_ url: URL) {
    NSWorkspace.shared.open(url)
  }

  private func cursor(for shape: ghostty_action_mouse_shape_e) -> NSCursor {
    switch shape {
    case GHOSTTY_MOUSE_SHAPE_TEXT, GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT:
      return .iBeam
    case GHOSTTY_MOUSE_SHAPE_POINTER:
      return .pointingHand
    case GHOSTTY_MOUSE_SHAPE_GRAB:
      return .openHand
    case GHOSTTY_MOUSE_SHAPE_GRABBING:
      return .closedHand
    case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
      return .crosshair
    case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED, GHOSTTY_MOUSE_SHAPE_NO_DROP:
      return .operationNotAllowed
    case GHOSTTY_MOUSE_SHAPE_E_RESIZE:
      return .resizeRight
    case GHOSTTY_MOUSE_SHAPE_W_RESIZE:
      return .resizeLeft
    case GHOSTTY_MOUSE_SHAPE_N_RESIZE:
      return .resizeUp
    case GHOSTTY_MOUSE_SHAPE_S_RESIZE:
      return .resizeDown
    case GHOSTTY_MOUSE_SHAPE_EW_RESIZE, GHOSTTY_MOUSE_SHAPE_COL_RESIZE:
      return .resizeLeftRight
    case GHOSTTY_MOUSE_SHAPE_NS_RESIZE, GHOSTTY_MOUSE_SHAPE_ROW_RESIZE:
      return .resizeUpDown
    default:
      return .arrow
    }
  }

  private func postUserNotification(_ notification: TerminalNotification) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized else { return }
      let content = UNMutableNotificationContent()
      content.title = notification.title
      content.body = notification.body
      content.sound = .default
      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      center.add(request)
    }
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
    let delta = TerminalInputPolicy.scrollDelta(
      deltaX: event.scrollingDeltaX,
      deltaY: event.scrollingDeltaY,
      hasPreciseDeltas: event.hasPreciseScrollingDeltas
    )
    ghostty_surface_mouse_scroll(surface, delta.x, delta.y, scrollMods(for: event))
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
    switch TerminalInputPolicy.mouseButton(for: buttonNumber) {
    case .left:
      return GHOSTTY_MOUSE_LEFT
    case .right:
      return GHOSTTY_MOUSE_RIGHT
    case .middle:
      return GHOSTTY_MOUSE_MIDDLE
    case .four:
      return GHOSTTY_MOUSE_FOUR
    case .five:
      return GHOSTTY_MOUSE_FIVE
    case .six:
      return GHOSTTY_MOUSE_SIX
    case .seven:
      return GHOSTTY_MOUSE_SEVEN
    case .eight:
      return GHOSTTY_MOUSE_EIGHT
    case .nine:
      return GHOSTTY_MOUSE_NINE
    case .ten:
      return GHOSTTY_MOUSE_TEN
    case .eleven:
      return GHOSTTY_MOUSE_ELEVEN
    case .unknown:
      return GHOSTTY_MOUSE_UNKNOWN
    }
  }

  private func scrollMods(for event: NSEvent) -> ghostty_input_scroll_mods_t {
    ghostty_input_scroll_mods_t(
      TerminalInputPolicy.scrollModifierBits(
        hasPreciseDeltas: event.hasPreciseScrollingDeltas,
        momentum: mouseMomentum(for: event.momentumPhase)
      )
    )
  }

  private func mouseMomentum(for phase: NSEvent.Phase) -> TerminalMouseMomentum {
    switch phase {
    case .began:
      return .began
    case .stationary:
      return .stationary
    case .changed:
      return .changed
    case .ended:
      return .ended
    case .cancelled:
      return .cancelled
    case .mayBegin:
      return .mayBegin
    default:
      return .noMomentum
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

    let text = TerminalTextInputPolicy.keyText(composed: composed, fallback: NSEventGhostty.characters(event))
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
    if let text = TerminalTextInputPolicy.keyPayload(text) {
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

  // MARK: - Drag and drop

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard canAcceptTerminalTransfer(from: sender.draggingPasteboard) else { return [] }
    setDropHighlightVisible(true)
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    canAcceptTerminalTransfer(from: sender.draggingPasteboard) ? .copy : []
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    setDropHighlightVisible(false)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    defer { setDropHighlightVisible(false) }
    guard let payload = terminalPayload(from: sender.draggingPasteboard, imageBeforeText: true) else { return false }
    window?.makeFirstResponder(self)
    sendTextToTerminal(payload)
    return true
  }

  private func setDropHighlightVisible(_ visible: Bool) {
    guard dropHighlightVisible != visible else { return }
    dropHighlightVisible = visible
    layer?.borderWidth = visible ? 2 : 0
    layer?.borderColor = visible ? NSColor.controlAccentColor.cgColor : nil
  }

  // MARK: - Clipboard

  @objc func copy(_ sender: Any?) {
    copySelection(cleaned: true)
  }

  @objc func copyRaw(_ sender: Any?) {
    copySelection(cleaned: false)
  }

  @objc func cut(_ sender: Any?) {
    copy(sender)
  }

  @objc func paste(_ sender: Any?) {
    guard let payload = terminalPayload(from: NSPasteboard.general, imageBeforeText: false) else { return }
    sendTextToTerminal(payload)
  }

  override func selectAll(_ sender: Any?) {
    // Terminal select-all needs scrollback-aware support from libghostty.
    // Keep the selector present for menu validation, but disabled for now.
  }

  func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(copy(_:)), #selector(copyRaw(_:)), #selector(cut(_:)):
      return selectedText != nil
    case #selector(paste(_:)):
      return canAcceptTerminalTransfer(from: NSPasteboard.general)
    case #selector(selectAll(_:)):
      return false
    default:
      return true
    }
  }

  private func copySelection(cleaned: Bool) {
    guard let selectedText else { return }
    let text = cleaned ? TerminalCopyPolicy().cleaned(selectedText) : selectedText
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  private func sendTextToTerminal(_ text: String) {
    guard let surface, let payload = TerminalTextInputPolicy.textPayload(text) else { return }
    payload.withCString { ptr in
      ghostty_surface_text(surface, ptr, UInt(payload.utf8.count))
    }
  }

  private static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [
    NSPasteboard.PasteboardType("public.png"),
    NSPasteboard.PasteboardType("public.jpeg"),
    NSPasteboard.PasteboardType("public.jpg"),
    NSPasteboard.PasteboardType("public.tiff"),
    NSPasteboard.PasteboardType("public.gif"),
    NSPasteboard.PasteboardType("org.webmproject.webp"),
  ]

  private static let terminalDragTypes: [NSPasteboard.PasteboardType] =
    [.fileURL, .URL, .string] + imagePasteboardTypes

  private func canAcceptTerminalTransfer(from pasteboard: NSPasteboard) -> Bool {
    pasteboard.canReadItem(withDataConformingToTypes: Self.terminalDragTypes.map(\.rawValue))
  }

  private func terminalPayload(from pasteboard: NSPasteboard, imageBeforeText: Bool) -> String? {
    if let paths = pasteboardFileURLs(pasteboard), let payload = TerminalTransferPolicy.pathPayload(for: paths) {
      return payload
    }
    if imageBeforeText, let payload = imagePayload(from: pasteboard) {
      return payload
    }
    if let text = TerminalTextInputPolicy.textPayload(pasteboard.string(forType: .string)) {
      return text
    }
    if let payload = imagePayload(from: pasteboard) {
      return payload
    }
    return TerminalTextInputPolicy.textPayload(pasteboard.string(forType: .URL))
  }

  private func pasteboardFileURLs(_ pasteboard: NSPasteboard) -> [URL]? {
    guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return nil }
    let fileURLs = urls.filter(\.isFileURL)
    return fileURLs.isEmpty ? nil : fileURLs
  }

  private func imagePayload(from pasteboard: NSPasteboard) -> String? {
    for type in Self.imagePasteboardTypes {
      guard let data = pasteboard.data(forType: type) else { continue }
      guard let url = try? imageStore.writeImage(data, contentType: type.rawValue) else { continue }
      return TerminalTransferPolicy.pathPayload(for: [url])
    }
    return nil
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
    guard let text = TerminalTextInputPolicy.insertionText(from: string) else { return }

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
