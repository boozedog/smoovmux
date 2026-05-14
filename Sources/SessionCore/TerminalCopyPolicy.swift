import Foundation

public enum TerminalCopyMode: Sendable, Equatable {
  case raw
  case cleaned
}

public struct TerminalCopyPolicy: Sendable {
  public init() {}

  public static func mode(cleanupEnabled: Bool) -> TerminalCopyMode {
    cleanupEnabled ? .cleaned : .raw
  }

  public func cleaned(_ text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var output: [String] = []
    var proseLines: [String] = []
    var codeLines: [String] = []
    var inCodeFence = false

    func appendProseParagraph() {
      guard !proseLines.isEmpty else { return }
      if output.last?.isEmpty == false {
        output.append("")
      }
      output.append(collapseWhitespace(proseLines.joined(separator: " ")))
      proseLines = []
    }

    func appendCodeLine() {
      guard !codeLines.isEmpty else { return }
      output.append(codeLines.joined())
      codeLines = []
    }

    for rawLine in lines {
      let line = stripClaudePrompt(from: rawLine).trimmingCharacters(in: .whitespaces)

      if line.hasPrefix("```") {
        if inCodeFence {
          appendCodeLine()
          output.append(line)
          inCodeFence = false
        } else {
          appendProseParagraph()
          if output.last?.isEmpty == false {
            output.append("")
          }
          output.append(line)
          inCodeFence = true
        }
        continue
      }

      if inCodeFence {
        if line.isEmpty {
          appendCodeLine()
          output.append("")
        } else {
          codeLines.append(line)
          if line.hasSuffix("\\") {
            appendCodeLine()
          }
        }
        continue
      }

      if line.isEmpty {
        appendProseParagraph()
      } else {
        proseLines.append(line)
      }
    }

    if inCodeFence {
      appendCodeLine()
    } else {
      appendProseParagraph()
    }

    return output.joined(separator: "\n")
  }

  private func stripClaudePrompt(from line: String) -> String {
    guard line.hasPrefix("❯") else { return line }

    let afterPrompt = line.dropFirst()
    let contentStart = afterPrompt.firstIndex { !$0.isWhitespace } ?? afterPrompt.endIndex
    return String(afterPrompt[contentStart...])
  }

  private func collapseWhitespace(_ text: String) -> String {
    var result = ""
    var previousWasWhitespace = false

    for character in text {
      if character.isWhitespace {
        if !previousWasWhitespace {
          result.append(" ")
        }
        previousWasWhitespace = true
      } else {
        result.append(character)
        previousWasWhitespace = false
      }
    }

    return result
  }
}
