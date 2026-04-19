import Foundation

/// Namespace for tmux `-CC` control-mode constants. Types live at the module
/// scope (`TmuxCC.Parser`, `TmuxCC.Token`) via `import TmuxCC`.
public enum TmuxCC {
  /// The flag passed to `tmux` to enable control mode.
  public static let controlModeFlag = "-CC"
}
