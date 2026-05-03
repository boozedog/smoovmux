import AppKit
import GhosttyKit
import SessionCore
import SmoovLog
import WorkspaceSidebar

/// Thin wrapper around `ghostty_app_t` + `ghostty_config_t`. One instance
/// per process, owned by `AppDelegate`. The six runtime callbacks libghostty
/// requires (`ghostty_runtime_config_s`) are routed through `@convention(c)`
/// trampolines that hop back to the main actor before touching Swift state.
///
/// Smoovmux loads bundled Ghostty defaults before the user's
/// `~/.config/smoovmux/config` so terminal preferences have app defaults while
/// still allowing user overrides. We do not load CLI args because smoovmux owns
/// its own process arguments.
///
/// What's deliberately *not* done:
/// - Terminal-initiated clipboard access (OSC 52 / selection clipboard) is
///   blocked by default. User paste is handled by `SmoovSurfaceView` instead.
/// - `action_cb` logs unknown actions and returns `true`. We'll expand in
///   later milestones as specific actions matter (e.g. window close).
@MainActor
final class GhosttyApp {
  enum InitError: Error {
    case ghosttyInit(Int32)
    case configNew
    case appNew
  }

  nonisolated(unsafe) let cValue: ghostty_app_t
  nonisolated(unsafe) private var config: ghostty_config_t

  init() throws {
    let rc = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
    if rc != 0 {
      throw InitError.ghosttyInit(rc)
    }

    guard let config = ghostty_config_new() else {
      throw InitError.configNew
    }
    Self.loadSmoovmuxDefaults(into: config)
    ghostty_config_finalize(config)
    self.config = config

    var runtimeConfig = ghostty_runtime_config_s(
      userdata: nil,
      supports_selection_clipboard: false,
      wakeup_cb: Self.wakeupCallback,
      action_cb: Self.actionCallback,
      read_clipboard_cb: Self.readClipboardCallback,
      confirm_read_clipboard_cb: Self.confirmReadClipboardCallback,
      write_clipboard_cb: Self.writeClipboardCallback,
      close_surface_cb: Self.closeSurfaceCallback
    )

    guard let app = ghostty_app_new(&runtimeConfig, config) else {
      ghostty_config_free(config)
      throw InitError.appNew
    }
    self.cValue = app

    ghostty_app_set_focus(app, NSApp.isActive)
  }

  deinit {
    ghostty_app_free(cValue)
    ghostty_config_free(config)
  }

  func tick() {
    ghostty_app_tick(cValue)
  }

  func reloadConfig(surface: ghostty_surface_t?, soft: Bool) {
    if soft {
      guard let surface else { return }
      ghostty_surface_update_config(surface, config)
      return
    }

    guard let newConfig = Self.makeSmoovmuxConfig() else { return }
    if let surface {
      ghostty_surface_update_config(surface, newConfig)
      ghostty_config_free(newConfig)
    } else {
      let oldConfig = config
      config = newConfig
      ghostty_app_update_config(cValue, newConfig)
      ghostty_config_free(oldConfig)
    }
  }

  func reloadConfig(soft: Bool) {
    if soft {
      ghostty_app_update_config(cValue, config)
      return
    }
    reloadConfig(surface: nil, soft: false)
  }

  private static func makeSmoovmuxConfig() -> ghostty_config_t? {
    guard let config = ghostty_config_new() else { return nil }
    loadSmoovmuxDefaults(into: config)
    ghostty_config_finalize(config)
    return config
  }

  private static func loadSmoovmuxDefaults(into config: ghostty_config_t) {
    if let bundledDefaultsURL = Bundle.main.url(
      forResource: SmoovmuxConfig.bundledDefaultConfigName,
      withExtension: nil
    ) {
      ghostty_config_load_file(config, bundledDefaultsURL.path)
    }

    if FileManager.default.fileExists(atPath: SmoovmuxConfig.configURL.path) {
      ghostty_config_load_file(config, SmoovmuxConfig.configURL.path)
      ghostty_config_load_recursive_files(config)
    }
  }

  // MARK: - Runtime callbacks
  //
  // Every callback is `@convention(c)` so libghostty can call it. Wakeup is
  // called from arbitrary threads; everything else is main-thread-only in
  // upstream's implementation, but we defensively dispatch anything that
  // touches Swift state back to main.

  private static let wakeupCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    DispatchQueue.main.async {
      if let delegate = NSApp.delegate as? AppDelegate {
        delegate.ghosttyApp?.tick()
      }
    }
  }

  private static let actionCallback: @convention(c) (ghostty_app_t?, ghostty_target_s, ghostty_action_s) -> Bool = {
    _, target, action in
    switch action.tag {
    case GHOSTTY_ACTION_NEW_SPLIT:
      guard let surfaceView = surfaceView(from: target) else { return false }
      DispatchQueue.main.async {
        surfaceView.handleGhosttySplitAction(action.action.new_split)
      }
      return true
    case GHOSTTY_ACTION_CLOSE_WINDOW:
      guard let surfaceView = surfaceView(from: target) else { return false }
      DispatchQueue.main.async {
        surfaceView.handleGhosttyCloseAction()
      }
      return true
    case GHOSTTY_ACTION_PWD:
      guard let surfaceView = surfaceView(from: target), let pwd = action.action.pwd.pwd else { return false }
      let cwd = String(cString: pwd)
      DispatchQueue.main.async {
        surfaceView.handleGhosttyPwdAction(cwd)
      }
      return true
    case GHOSTTY_ACTION_SET_TITLE:
      guard let surfaceView = surfaceView(from: target),
        let title = action.action.set_title.title
      else { return false }
      let value = String(cString: title)
      DispatchQueue.main.async {
        surfaceView.handleGhosttySetTitleAction(value)
      }
      return true
    case GHOSTTY_ACTION_SET_TAB_TITLE:
      guard let surfaceView = surfaceView(from: target),
        let title = action.action.set_tab_title.title
      else { return false }
      let value = String(cString: title)
      DispatchQueue.main.async {
        surfaceView.handleGhosttySetTitleAction(value)
      }
      return true
    case GHOSTTY_ACTION_RING_BELL:
      guard let surfaceView = surfaceView(from: target) else { return false }
      DispatchQueue.main.async {
        surfaceView.handleGhosttyBellAction()
      }
      return true
    case GHOSTTY_ACTION_PROGRESS_REPORT:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let progress = progressPercent(from: action.action.progress_report)
      DispatchQueue.main.async {
        surfaceView.handleGhosttyProgressAction(progress)
      }
      return true
    case GHOSTTY_ACTION_COMMAND_FINISHED:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let rawExitCode = action.action.command_finished.exit_code
      let exitCode: Int16? = rawExitCode >= 0 ? rawExitCode : nil
      DispatchQueue.main.async {
        surfaceView.handleGhosttyCommandFinishedAction(exitCode: exitCode)
      }
      return true
    case GHOSTTY_ACTION_OPEN_URL:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let openURLAction = action.action.open_url
      let urlText = TerminalExternalActionPolicy.string(
        from: UnsafeRawPointer(openURLAction.url)?.assumingMemoryBound(to: UInt8.self),
        length: Int(openURLAction.len)
      )
      guard let url = TerminalExternalActionPolicy.openURL(from: urlText) else { return false }
      DispatchQueue.main.async {
        surfaceView.handleGhosttyOpenURLAction(url)
      }
      return true
    case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let exitCode = action.action.child_exited.exit_code
      DispatchQueue.main.async {
        surfaceView.handleGhosttyChildExitedAction(exitCode: exitCode)
      }
      return true
    case GHOSTTY_ACTION_RENDERER_HEALTH:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let healthy = action.action.renderer_health == GHOSTTY_RENDERER_HEALTH_HEALTHY
      DispatchQueue.main.async {
        surfaceView.handleGhosttyRendererHealthAction(healthy: healthy)
      }
      return true
    case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
      guard let surfaceView = surfaceView(from: target),
        let titlePointer = action.action.desktop_notification.title,
        let bodyPointer = action.action.desktop_notification.body
      else { return false }
      let title = String(cString: titlePointer)
      let body = String(cString: bodyPointer)
      DispatchQueue.main.async {
        surfaceView.handleGhosttyDesktopNotificationAction(title: title, body: body)
      }
      return true
    case GHOSTTY_ACTION_MOUSE_SHAPE:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let shape = action.action.mouse_shape
      DispatchQueue.main.async {
        surfaceView.handleGhosttyMouseShapeAction(shape)
      }
      return true
    case GHOSTTY_ACTION_MOUSE_VISIBILITY:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let visibility = action.action.mouse_visibility
      DispatchQueue.main.async {
        surfaceView.handleGhosttyMouseVisibilityAction(visibility)
      }
      return true
    case GHOSTTY_ACTION_MOUSE_OVER_LINK:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let linkAction = action.action.mouse_over_link
      let urlText = TerminalExternalActionPolicy.string(
        from: UnsafeRawPointer(linkAction.url)?.assumingMemoryBound(to: UInt8.self),
        length: Int(linkAction.len)
      )
      let url = TerminalExternalActionPolicy.openURL(from: urlText)
      DispatchQueue.main.async {
        surfaceView.handleGhosttyMouseOverLinkAction(url)
      }
      return true
    case GHOSTTY_ACTION_COLOR_CHANGE:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let colorChange = terminalColorChange(from: action.action.color_change)
      DispatchQueue.main.async {
        surfaceView.handleGhosttyColorChangeAction(colorChange)
      }
      return true
    case GHOSTTY_ACTION_RELOAD_CONFIG:
      if let surfaceView = surfaceView(from: target) {
        let soft = action.action.reload_config.soft
        DispatchQueue.main.async {
          surfaceView.handleGhosttyReloadConfigAction(soft: soft)
        }
      } else {
        DispatchQueue.main.async {
          (NSApp.delegate as? AppDelegate)?.ghosttyApp?.reloadConfig(soft: action.action.reload_config.soft)
        }
      }
      return true
    case GHOSTTY_ACTION_CONFIG_CHANGE:
      guard let surfaceView = surfaceView(from: target) else { return true }
      DispatchQueue.main.async {
        surfaceView.handleGhosttyConfigChangeAction()
      }
      return true
    case GHOSTTY_ACTION_START_SEARCH:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let needle = action.action.start_search.needle.map { String(cString: $0) }
      DispatchQueue.main.async {
        surfaceView.handleGhosttyStartSearchAction(needle: needle)
      }
      return true
    case GHOSTTY_ACTION_END_SEARCH:
      guard let surfaceView = surfaceView(from: target) else { return false }
      DispatchQueue.main.async {
        surfaceView.handleGhosttyEndSearchAction()
      }
      return true
    case GHOSTTY_ACTION_SEARCH_TOTAL:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let total = nonnegativeInt(action.action.search_total.total)
      DispatchQueue.main.async {
        surfaceView.handleGhosttySearchTotalAction(total)
      }
      return true
    case GHOSTTY_ACTION_SEARCH_SELECTED:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let selected = nonnegativeInt(action.action.search_selected.selected)
      DispatchQueue.main.async {
        surfaceView.handleGhosttySearchSelectedAction(selected)
      }
      return true
    case GHOSTTY_ACTION_SCROLLBAR:
      guard let surfaceView = surfaceView(from: target) else { return false }
      let value = action.action.scrollbar
      let scrollbar = TerminalScrollbar(total: value.total, offset: value.offset, length: value.len)
      DispatchQueue.main.async {
        surfaceView.handleGhosttyScrollbarAction(scrollbar)
      }
      return true
    default:
      SmoovLog.info("ghostty action tag=\(action.tag.rawValue) (unhandled)")
      return true
    }
  }

  private static func progressPercent(from progress: ghostty_action_progress_report_s) -> Int? {
    switch progress.state {
    case GHOSTTY_PROGRESS_STATE_REMOVE:
      return nil
    case GHOSTTY_PROGRESS_STATE_SET:
      return progress.progress >= 0 ? Int(progress.progress) : nil
    default:
      return nil
    }
  }

  private static func terminalColorChange(from change: ghostty_action_color_change_s) -> TerminalColorChange {
    let kind: TerminalColorKind
    switch change.kind {
    case GHOSTTY_ACTION_COLOR_KIND_FOREGROUND:
      kind = .foreground
    case GHOSTTY_ACTION_COLOR_KIND_BACKGROUND:
      kind = .background
    case GHOSTTY_ACTION_COLOR_KIND_CURSOR:
      kind = .cursor
    default:
      kind = .palette(Int(change.kind.rawValue))
    }
    return TerminalColorChange(kind: kind, red: change.r, green: change.g, blue: change.b)
  }

  private static func nonnegativeInt(_ value: Int) -> Int? {
    value >= 0 ? value : nil
  }

  private static func surfaceView(from target: ghostty_target_s) -> SmoovSurfaceView? {
    guard target.tag == GHOSTTY_TARGET_SURFACE,
      let surface = target.target.surface,
      let userdata = ghostty_surface_userdata(surface)
    else {
      return nil
    }
    return Unmanaged<SmoovSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
  }

  private static let readClipboardCallback:
    @convention(c) (
      UnsafeMutableRawPointer?, ghostty_clipboard_e, UnsafeMutableRawPointer?
    ) -> Bool = { _, _, _ in
      // Privacy policy: terminal-initiated clipboard reads (including OSC 52)
      // are blocked by default. User paste goes through SmoovSurfaceView.paste.
      false
    }

  private static let confirmReadClipboardCallback:
    @convention(c) (
      UnsafeMutableRawPointer?,
      UnsafePointer<CChar>?,
      UnsafeMutableRawPointer?,
      ghostty_clipboard_request_e
    ) -> Void = { _, _, _, _ in
      // No confirmation UI exists yet, so clipboard reads remain blocked.
    }

  private static let writeClipboardCallback:
    @convention(c) (
      UnsafeMutableRawPointer?,
      ghostty_clipboard_e,
      UnsafePointer<ghostty_clipboard_content_s>?,
      Int,
      Bool
    ) -> Void = { _, _, _, _, _ in
      // Privacy policy: terminal-initiated clipboard writes are blocked by
      // default. Do not inspect or log clipboard payloads here.
    }

  private static let closeSurfaceCallback: @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void = { _, _ in
    // The surface's `deinit` calls `ghostty_surface_free`. Nothing to do
    // here for M1 — in later milestones this is where we'd close the
    // containing window/tab if the process exited.
  }
}
