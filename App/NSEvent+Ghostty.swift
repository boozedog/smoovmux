import AppKit
import GhosttyKit

/// `NSEvent` → `ghostty_input_key_s` translation. Pure functions so the
/// logic is unit-testable without a window or display.
///
/// The keycode table is mirrored from upstream Ghostty
/// (`ghostty/macos/Sources/Ghostty/Ghostty.Input.swift`
/// `Ghostty.Input.Key.keyCode`), which in turn mirrors
/// `ghostty/src/input/keycodes.zig`. Only the subset with real Mac keycodes
/// is included; everything else maps to `GHOSTTY_KEY_UNIDENTIFIED`.
///
/// Modifier flags follow upstream's heuristic: control and command never
/// contribute to text translation, so `consumed_mods` strips them.
enum NSEventGhostty {
  /// Build a ghostty key event from an NSEvent. The `text` pointer is left
  /// nil — callers fill that in within a `withCString` closure since the
  /// C-string lifetime has to outlive `ghostty_surface_key`.
  static func keyEvent(
    _ event: NSEvent,
    action: ghostty_input_action_e
  ) -> ghostty_input_key_s {
    var keyEv = ghostty_input_key_s()
    keyEv.action = action
    keyEv.keycode = UInt32(event.keyCode)
    keyEv.text = nil
    keyEv.composing = false
    keyEv.mods = mods(event.modifierFlags)
    keyEv.consumed_mods = mods(event.modifierFlags.subtracting([.control, .command]))
    keyEv.unshifted_codepoint = 0
    if event.type == .keyDown || event.type == .keyUp,
      let chars = event.characters(byApplyingModifiers: []),
      let scalar = chars.unicodeScalars.first
    {
      keyEv.unshifted_codepoint = scalar.value
    }
    return keyEv
  }

  /// Translate `NSEvent.ModifierFlags` to Ghostty's `ghostty_input_mods_e`
  /// bitmask. Handles both unsided (shift/ctrl/alt/cmd) and right-sided
  /// flags exposed via `NX_DEVICER*` private masks.
  static func mods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var out: UInt32 = GHOSTTY_MODS_NONE.rawValue
    if flags.contains(.shift) { out |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { out |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { out |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { out |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { out |= GHOSTTY_MODS_CAPS.rawValue }
    let raw = flags.rawValue
    if raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { out |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCTLKEYMASK) != 0 { out |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERALTKEYMASK) != 0 { out |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
    if raw & UInt(NX_DEVICERCMDKEYMASK) != 0 { out |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
    return ghostty_input_mods_e(out)
  }

  /// Map a macOS virtual keycode to Ghostty's key enum. Returns
  /// `GHOSTTY_KEY_UNIDENTIFIED` for keys we don't have a mapping for —
  /// libghostty still receives the raw keycode via `ghostty_input_key_s.keycode`.
  // swiftlint:disable cyclomatic_complexity function_body_length
  static func keyCode(_ keyCode: UInt16) -> ghostty_input_key_e {
    switch keyCode {
    // Letters
    case 0x0000: return GHOSTTY_KEY_A
    case 0x000b: return GHOSTTY_KEY_B
    case 0x0008: return GHOSTTY_KEY_C
    case 0x0002: return GHOSTTY_KEY_D
    case 0x000e: return GHOSTTY_KEY_E
    case 0x0003: return GHOSTTY_KEY_F
    case 0x0005: return GHOSTTY_KEY_G
    case 0x0004: return GHOSTTY_KEY_H
    case 0x0022: return GHOSTTY_KEY_I
    case 0x0026: return GHOSTTY_KEY_J
    case 0x0028: return GHOSTTY_KEY_K
    case 0x0025: return GHOSTTY_KEY_L
    case 0x002e: return GHOSTTY_KEY_M
    case 0x002d: return GHOSTTY_KEY_N
    case 0x001f: return GHOSTTY_KEY_O
    case 0x0023: return GHOSTTY_KEY_P
    case 0x000c: return GHOSTTY_KEY_Q
    case 0x000f: return GHOSTTY_KEY_R
    case 0x0001: return GHOSTTY_KEY_S
    case 0x0011: return GHOSTTY_KEY_T
    case 0x0020: return GHOSTTY_KEY_U
    case 0x0009: return GHOSTTY_KEY_V
    case 0x000d: return GHOSTTY_KEY_W
    case 0x0007: return GHOSTTY_KEY_X
    case 0x0010: return GHOSTTY_KEY_Y
    case 0x0006: return GHOSTTY_KEY_Z

    // Digits
    case 0x001d: return GHOSTTY_KEY_DIGIT_0
    case 0x0012: return GHOSTTY_KEY_DIGIT_1
    case 0x0013: return GHOSTTY_KEY_DIGIT_2
    case 0x0014: return GHOSTTY_KEY_DIGIT_3
    case 0x0015: return GHOSTTY_KEY_DIGIT_4
    case 0x0017: return GHOSTTY_KEY_DIGIT_5
    case 0x0016: return GHOSTTY_KEY_DIGIT_6
    case 0x001a: return GHOSTTY_KEY_DIGIT_7
    case 0x001c: return GHOSTTY_KEY_DIGIT_8
    case 0x0019: return GHOSTTY_KEY_DIGIT_9

    // Punctuation
    case 0x0032: return GHOSTTY_KEY_BACKQUOTE
    case 0x002a: return GHOSTTY_KEY_BACKSLASH
    case 0x0021: return GHOSTTY_KEY_BRACKET_LEFT
    case 0x001e: return GHOSTTY_KEY_BRACKET_RIGHT
    case 0x002b: return GHOSTTY_KEY_COMMA
    case 0x0018: return GHOSTTY_KEY_EQUAL
    case 0x001b: return GHOSTTY_KEY_MINUS
    case 0x002f: return GHOSTTY_KEY_PERIOD
    case 0x0027: return GHOSTTY_KEY_QUOTE
    case 0x0029: return GHOSTTY_KEY_SEMICOLON
    case 0x002c: return GHOSTTY_KEY_SLASH
    case 0x000a: return GHOSTTY_KEY_INTL_BACKSLASH
    case 0x005e: return GHOSTTY_KEY_INTL_RO
    case 0x005d: return GHOSTTY_KEY_INTL_YEN

    // Functional keys
    case 0x003a: return GHOSTTY_KEY_ALT_LEFT
    case 0x003d: return GHOSTTY_KEY_ALT_RIGHT
    case 0x0033: return GHOSTTY_KEY_BACKSPACE
    case 0x0039: return GHOSTTY_KEY_CAPS_LOCK
    case 0x006e: return GHOSTTY_KEY_CONTEXT_MENU
    case 0x003b: return GHOSTTY_KEY_CONTROL_LEFT
    case 0x003e: return GHOSTTY_KEY_CONTROL_RIGHT
    case 0x0024: return GHOSTTY_KEY_ENTER
    case 0x0037: return GHOSTTY_KEY_META_LEFT
    case 0x0036: return GHOSTTY_KEY_META_RIGHT
    case 0x0038: return GHOSTTY_KEY_SHIFT_LEFT
    case 0x003c: return GHOSTTY_KEY_SHIFT_RIGHT
    case 0x0031: return GHOSTTY_KEY_SPACE
    case 0x0030: return GHOSTTY_KEY_TAB

    // Control pad
    case 0x0075: return GHOSTTY_KEY_DELETE
    case 0x0077: return GHOSTTY_KEY_END
    case 0x0073: return GHOSTTY_KEY_HOME
    case 0x0072: return GHOSTTY_KEY_INSERT
    case 0x0079: return GHOSTTY_KEY_PAGE_DOWN
    case 0x0074: return GHOSTTY_KEY_PAGE_UP

    // Arrows
    case 0x007d: return GHOSTTY_KEY_ARROW_DOWN
    case 0x007b: return GHOSTTY_KEY_ARROW_LEFT
    case 0x007c: return GHOSTTY_KEY_ARROW_RIGHT
    case 0x007e: return GHOSTTY_KEY_ARROW_UP

    // Numpad
    case 0x0047: return GHOSTTY_KEY_NUM_LOCK
    case 0x0052: return GHOSTTY_KEY_NUMPAD_0
    case 0x0053: return GHOSTTY_KEY_NUMPAD_1
    case 0x0054: return GHOSTTY_KEY_NUMPAD_2
    case 0x0055: return GHOSTTY_KEY_NUMPAD_3
    case 0x0056: return GHOSTTY_KEY_NUMPAD_4
    case 0x0057: return GHOSTTY_KEY_NUMPAD_5
    case 0x0058: return GHOSTTY_KEY_NUMPAD_6
    case 0x0059: return GHOSTTY_KEY_NUMPAD_7
    case 0x005b: return GHOSTTY_KEY_NUMPAD_8
    case 0x005c: return GHOSTTY_KEY_NUMPAD_9
    case 0x0045: return GHOSTTY_KEY_NUMPAD_ADD
    case 0x005f: return GHOSTTY_KEY_NUMPAD_COMMA
    case 0x0041: return GHOSTTY_KEY_NUMPAD_DECIMAL
    case 0x004b: return GHOSTTY_KEY_NUMPAD_DIVIDE
    case 0x004c: return GHOSTTY_KEY_NUMPAD_ENTER
    case 0x0051: return GHOSTTY_KEY_NUMPAD_EQUAL
    case 0x0043: return GHOSTTY_KEY_NUMPAD_MULTIPLY
    case 0x004e: return GHOSTTY_KEY_NUMPAD_SUBTRACT

    // Function keys
    case 0x0035: return GHOSTTY_KEY_ESCAPE
    case 0x007a: return GHOSTTY_KEY_F1
    case 0x0078: return GHOSTTY_KEY_F2
    case 0x0063: return GHOSTTY_KEY_F3
    case 0x0076: return GHOSTTY_KEY_F4
    case 0x0060: return GHOSTTY_KEY_F5
    case 0x0061: return GHOSTTY_KEY_F6
    case 0x0062: return GHOSTTY_KEY_F7
    case 0x0064: return GHOSTTY_KEY_F8
    case 0x0065: return GHOSTTY_KEY_F9
    case 0x006d: return GHOSTTY_KEY_F10
    case 0x0067: return GHOSTTY_KEY_F11
    case 0x006f: return GHOSTTY_KEY_F12
    case 0x0069: return GHOSTTY_KEY_F13
    case 0x006b: return GHOSTTY_KEY_F14
    case 0x0071: return GHOSTTY_KEY_F15
    case 0x006a: return GHOSTTY_KEY_F16
    case 0x0040: return GHOSTTY_KEY_F17
    case 0x004f: return GHOSTTY_KEY_F18
    case 0x0050: return GHOSTTY_KEY_F19
    case 0x005a: return GHOSTTY_KEY_F20

    // Media
    case 0x0049: return GHOSTTY_KEY_AUDIO_VOLUME_DOWN
    case 0x004a: return GHOSTTY_KEY_AUDIO_VOLUME_MUTE
    case 0x0048: return GHOSTTY_KEY_AUDIO_VOLUME_UP

    default: return GHOSTTY_KEY_UNIDENTIFIED
    }
  }
  // swiftlint:enable cyclomatic_complexity function_body_length

  /// Return the text to send to libghostty for a given event, or `nil` if
  /// none should be sent. Control characters are stripped (libghostty
  /// encodes those itself via the keycode path) and Cocoa's private-use-area
  /// function-key characters are dropped.
  static func characters(_ event: NSEvent) -> String? {
    guard let chars = event.characters else { return nil }
    if chars.count == 1, let scalar = chars.unicodeScalars.first {
      if scalar.value < 0x20 {
        return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
      }
      if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
        return nil
      }
    }
    return chars
  }
}
