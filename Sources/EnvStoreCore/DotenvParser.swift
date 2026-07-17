import Foundation

public struct DotenvParser: Sendable {
  public init() {}

  public func parse(_ input: String) -> DotenvParseResult {
    let lines = normalizedLines(from: input)
    var accumulator = ParseAccumulator()
    var lineIndex = 0

    while lineIndex < lines.count {
      parseLine(lines, at: &lineIndex, into: &accumulator)
    }

    return accumulator.result
  }

  private func parseLine(
    _ lines: [String],
    at lineIndex: inout Int,
    into accumulator: inout ParseAccumulator
  ) {
    let sourceLine = lineIndex + 1
    let line = lines[lineIndex]
    lineIndex += 1

    guard !line.contains("\0") else {
      accumulator.addError(.nullByte, line: sourceLine)
      return
    }

    let content = assignmentContent(from: line)
    guard !content.isEmpty, !content.hasPrefix("#") else {
      return
    }

    guard let equalsIndex = content.firstIndex(of: "=") else {
      accumulator.addError(.invalidKey, line: sourceLine)
      return
    }

    let key = content[..<equalsIndex].trimmingCharacters(in: .whitespaces)
    guard isValidKey(key) else {
      accumulator.addError(.invalidKey, line: sourceLine, key: key.isEmpty ? nil : key)
      return
    }

    let valueStart = content.index(after: equalsIndex)
    let rawValue = content[valueStart...].trimmingLeadingWhitespace()
    let parsedValue = parseValue(
      rawValue,
      remainingLines: lines,
      nextLineIndex: &lineIndex,
      sourceLine: sourceLine,
      accumulator: &accumulator
    )

    if let parsedValue {
      accumulator.addVariable(key: key, value: parsedValue, sourceLine: sourceLine)
    }
  }

  private func assignmentContent(from line: String) -> String {
    let trimmed = line.trimmingLeadingWhitespace()
    guard trimmed.hasPrefix("export") else {
      return trimmed
    }

    let prefixEnd = trimmed.index(trimmed.startIndex, offsetBy: 6)
    guard prefixEnd < trimmed.endIndex, trimmed[prefixEnd].isHorizontalWhitespace else {
      return trimmed
    }

    return trimmed[prefixEnd...].trimmingLeadingWhitespace()
  }

  private func parseValue(
    _ rawValue: String,
    remainingLines: [String],
    nextLineIndex: inout Int,
    sourceLine: Int,
    accumulator: inout ParseAccumulator
  ) -> String? {
    guard let quote = rawValue.first, quote == "'" || quote == "\"" else {
      return parseUnquotedValue(rawValue)
    }

    let contentStart = rawValue.index(after: rawValue.startIndex)
    let firstSegment = String(rawValue[contentStart...])
    let outcome = parseQuotedValue(
      firstSegment: firstSegment,
      quote: quote,
      remainingLines: remainingLines,
      nextLineIndex: &nextLineIndex
    )

    if let nullByteLine = outcome.nullByteLine {
      accumulator.addError(.nullByte, line: nullByteLine)
      return nil
    }

    guard outcome.terminated else {
      accumulator.addError(.unterminatedQuote, line: sourceLine)
      return nil
    }

    return outcome.value
  }

  private func parseUnquotedValue(_ rawValue: String) -> String {
    let characters = Array(rawValue)

    for index in characters.indices where characters[index] == "#" {
      guard index > characters.startIndex,
        characters[characters.index(before: index)].isHorizontalWhitespace
      else {
        continue
      }

      return String(characters[..<index]).trimmingCharacters(in: .whitespaces)
    }

    return rawValue.trimmingCharacters(in: .whitespaces)
  }

  private func parseQuotedValue(
    firstSegment: String,
    quote: Character,
    remainingLines: [String],
    nextLineIndex: inout Int
  ) -> QuotedValueOutcome {
    var value = ""
    var segment = firstSegment
    var segmentLine = nextLineIndex
    var nullByteLine: Int?

    while true {
      if segment.contains("\0"), nullByteLine == nil {
        nullByteLine = segmentLine
      }

      if let closingIndex = closingQuoteIndex(in: segment, quote: quote) {
        let quotedContent = String(segment[..<closingIndex])
        value.append(decoded(quotedContent, quote: quote))
        appendUnquotedTail(after: closingIndex, in: segment, to: &value)
        return QuotedValueOutcome(value: value, terminated: true, nullByteLine: nullByteLine)
      }

      value.append(decoded(segment, quote: quote))
      guard nextLineIndex < remainingLines.count else {
        return QuotedValueOutcome(value: value, terminated: false, nullByteLine: nullByteLine)
      }

      value.append("\n")
      segment = remainingLines[nextLineIndex]
      nextLineIndex += 1
      segmentLine = nextLineIndex
    }
  }

  private func closingQuoteIndex(in segment: String, quote: Character) -> String.Index? {
    var isEscaped = false

    for index in segment.indices {
      let character = segment[index]
      if quote == "\"", character == "\\", !isEscaped {
        isEscaped = true
        continue
      }

      if character == quote, !isEscaped {
        return index
      }

      isEscaped = false
    }

    return nil
  }

  private func decoded(_ content: String, quote: Character) -> String {
    guard quote == "\"" else {
      return content
    }

    let characters = Array(content)
    var decoded = ""
    var index = 0

    while index < characters.count {
      let character = characters[index]
      guard character == "\\", index + 1 < characters.count else {
        decoded.append(character)
        index += 1
        continue
      }

      let escaped = characters[index + 1]
      switch escaped {
      case "n": decoded.append("\n")
      case "r": decoded.append("\r")
      case "t": decoded.append("\t")
      case "\\": decoded.append("\\")
      case "\"": decoded.append("\"")
      default:
        decoded.append("\\")
        decoded.append(escaped)
      }
      index += 2
    }

    return decoded
  }

  private func appendUnquotedTail(
    after quoteIndex: String.Index, in segment: String, to value: inout String
  ) {
    let tailStart = segment.index(after: quoteIndex)
    let tail = segment[tailStart...].trimmingLeadingWhitespace()
    guard !tail.isEmpty, !tail.hasPrefix("#") else {
      return
    }

    value.append(tail)
  }

  private func normalizedLines(from input: String) -> [String] {
    input
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
  }

  private func isValidKey(_ key: String) -> Bool {
    let bytes = Array(key.utf8)
    guard let first = bytes.first, first.isASCIIAlpha || first == 95 else {
      return false
    }

    return bytes.dropFirst().allSatisfy { $0.isASCIIAlpha || $0.isASCIIDigit || $0 == 95 }
  }
}

private struct ParseAccumulator {
  private var variablesByKey: [String: DotenvVariable] = [:]
  private var orderedKeys: [String] = []
  private(set) var issues: [DotenvIssue] = []

  var result: DotenvParseResult {
    DotenvParseResult(
      variables: orderedKeys.compactMap { variablesByKey[$0] },
      issues: issues
    )
  }

  mutating func addVariable(key: String, value: String, sourceLine: Int) {
    if variablesByKey[key] != nil {
      issues.append(
        DotenvIssue(severity: .warning, code: .duplicateKey, line: sourceLine, key: key))
    } else {
      orderedKeys.append(key)
    }

    variablesByKey[key] = DotenvVariable(key: key, value: value, sourceLine: sourceLine)
  }

  mutating func addError(_ code: DotenvIssue.Code, line: Int, key: String? = nil) {
    issues.append(DotenvIssue(severity: .error, code: code, line: line, key: key))
  }
}

private struct QuotedValueOutcome {
  let value: String
  let terminated: Bool
  let nullByteLine: Int?
}

extension Character {
  fileprivate var isHorizontalWhitespace: Bool {
    self == " " || self == "\t"
  }
}

extension StringProtocol {
  fileprivate func trimmingLeadingWhitespace() -> String {
    String(drop(while: \.isHorizontalWhitespace))
  }
}

extension UInt8 {
  fileprivate var isASCIIAlpha: Bool {
    (65...90).contains(self) || (97...122).contains(self)
  }

  fileprivate var isASCIIDigit: Bool {
    (48...57).contains(self)
  }
}
