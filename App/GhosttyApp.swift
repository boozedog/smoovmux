import AppKit
import GhosttyKit
import SmoovLog

/// Thin wrapper around `ghostty_app_t` + `ghostty_config_t`. One instance
/// per process, owned by `AppDelegate`. The six runtime callbacks libghostty
/// requires (`ghostty_runtime_config_s`) are routed through `@convention(c)`
/// trampolines that hop back to the main actor before touching Swift state.
///
/// Smoovmux loads Ghostty's default config files before finalizing so terminal
/// preferences such as font and colors match the user's Ghostty setup. We do
/// not load CLI args because smoovmux owns its own process arguments.
///
/// What's deliberately *not* done:
/// - No OSC 52 clipboard plumbing — stubs return `false`/no-op.
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
  nonisolated(unsafe) private let config: ghostty_config_t

  init() throws {
    let rc = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
    if rc != 0 {
      throw InitError.ghosttyInit(rc)
    }

    guard let config = ghostty_config_new() else {
      throw InitError.configNew
    }
    ghostty_config_load_default_files(config)
    ghostty_config_load_recursive_files(config)
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
    default:
      SmoovLog.info("ghostty action tag=\(action.tag.rawValue) (unhandled)")
      return true
    }
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
      false
    }

  private static let confirmReadClipboardCallback:
    @convention(c) (
      UnsafeMutableRawPointer?,
      UnsafePointer<CChar>?,
      UnsafeMutableRawPointer?,
      ghostty_clipboard_request_e
    ) -> Void = { _, _, _, _ in
    }

  private static let writeClipboardCallback:
    @convention(c) (
      UnsafeMutableRawPointer?,
      ghostty_clipboard_e,
      UnsafePointer<ghostty_clipboard_content_s>?,
      Int,
      Bool
    ) -> Void = { _, _, _, _, _ in
    }

  private static let closeSurfaceCallback: @convention(c) (UnsafeMutableRawPointer?, Bool) -> Void = { _, _ in
    // The surface's `deinit` calls `ghostty_surface_free`. Nothing to do
    // here for M1 — in later milestones this is where we'd close the
    // containing window/tab if the process exited.
  }
}
