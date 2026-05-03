import Foundation

public struct TerminalCopyPolicy: Sendable {
  public var promptPrefixes: [String]
  public var collapseBlankLines: Bool

  public init(
    promptPrefixes: [String] = ["❯", "➜", "$ ", "# ", "> "],
    collapseBlankLines: Bool = true
  ) {
    self.promptPrefixes = promptPrefixes
    self.collapseBlankLines = collapseBlankLines
  }

  public func cleaned(_ text: String) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    lines = lines.map { stripPromptPrefix(from: $0).trimmingCharacters(in: .whitespaces) }
    if collapseBlankLines {
      lines = collapseRunsOfBlankLines(lines)
    }
    return lines.joined(separator: "\n")
  }

  private func stripPromptPrefix(from line: String) -> String {
    let leadingWhitespaceCount = line.prefix { $0 == " " || $0 == "\t" }.count
    let leadingWhitespace = String(line.prefix(leadingWhitespaceCount))
    let remainder = String(line.dropFirst(leadingWhitespaceCount))

    for prefix in promptPrefixes where remainder.hasPrefix(prefix) {
      return leadingWhitespace + remainder.dropFirst(prefix.count)
    }
    return line
  }

  private func collapseRunsOfBlankLines(_ lines: [String]) -> [String] {
    var result: [String] = []
    var blankRun = 0
    for line in lines {
      if line.isEmpty {
        blankRun += 1
        if blankRun <= 2 {
          result.append(line)
        }
      } else {
        blankRun = 0
        result.append(line)
      }
    }
    return result
  }
}
