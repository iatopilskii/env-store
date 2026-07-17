import Foundation

public struct DotenvVariable: Codable, Equatable, Sendable {
  public let key: String
  public let value: String
  public let sourceLine: Int

  public init(key: String, value: String, sourceLine: Int) {
    self.key = key
    self.value = value
    self.sourceLine = sourceLine
  }
}

public struct DotenvIssue: Codable, Equatable, Sendable {
  public enum Severity: String, Codable, Sendable {
    case warning
    case error
  }

  public enum Code: String, Codable, Sendable {
    case duplicateKey = "duplicate_key"
    case invalidKey = "invalid_key"
    case nullByte = "null_byte"
    case unterminatedQuote = "unterminated_quote"
  }

  public let severity: Severity
  public let code: Code
  public let line: Int
  public let key: String?

  public init(severity: Severity, code: Code, line: Int, key: String? = nil) {
    self.severity = severity
    self.code = code
    self.line = line
    self.key = key
  }
}

public struct DotenvParseResult: Codable, Equatable, Sendable {
  public let variables: [DotenvVariable]
  public let issues: [DotenvIssue]

  public init(variables: [DotenvVariable], issues: [DotenvIssue]) {
    self.variables = variables
    self.issues = issues
  }

  public var warnings: [DotenvIssue] {
    issues.filter { $0.severity == .warning }
  }

  public var errors: [DotenvIssue] {
    issues.filter { $0.severity == .error }
  }

  public func value(for key: String) -> String? {
    variables.first { $0.key == key }?.value
  }
}
