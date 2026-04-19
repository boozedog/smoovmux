import Foundation

/// Decode tmux control mode octal escaping.
///
/// Per the tmux Control-Mode wiki, `%output` payloads have every byte less
/// than ASCII 32 and every `\` replaced with `\ooo` (backslash + three octal
/// digits). Without decoding, a CR LF sequence arrives as the eight literal
/// bytes `\015\012` and the terminal never sees a line break.
///
/// Malformed escape sequences (non-octal digit, or fewer than three digits
/// remaining in the input) are replaced with a single `?` rather than
/// silently dropped, so a protocol bug is visible at the terminal instead
/// of vanishing the rest of the payload.
///
/// Algorithm ported from ghostty's `decodeEscapedOutput` in
/// `src/terminal/tmux/control.zig` (PR ghostty-org/ghostty#12076).
func decodeTmuxOutput(_ input: Data) -> Data {
  var output = Data()
  output.reserveCapacity(input.count)

  var idx = input.startIndex
  while idx < input.endIndex {
    let byte = input[idx]
    if byte != 0x5c {  // '\'
      output.append(byte)
      idx = input.index(after: idx)
      continue
    }

    // Consume the backslash, then try to read three octal digits.
    var digitsEnd = input.index(after: idx)
    var value: UInt8 = 0
    var consumed = 0
    while consumed < 3, digitsEnd < input.endIndex {
      let digit = input[digitsEnd]
      if digit < 0x30 || digit > 0x37 { break }  // '0'..'7'
      // tmux only escapes bytes <32 and '\' (0o134 = 92), so value fits in UInt8.
      value = value &* 8 &+ (digit - 0x30)
      digitsEnd = input.index(after: digitsEnd)
      consumed += 1
    }

    output.append(consumed == 3 ? value : 0x3f)  // '?' on malformed
    idx = digitsEnd
  }

  return output
}
