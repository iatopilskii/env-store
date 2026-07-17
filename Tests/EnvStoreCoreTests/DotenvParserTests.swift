import Testing

@testable import EnvStoreCore

struct DotenvParserTests {
  @Test
  func parsesBasicAssignmentsCommentsAndExportPrefix() {
    let input = """
      # database
      export DATABASE_URL=postgres://localhost/app
      PORT=3000 # local port
      EMPTY=
      """

    let result = DotenvParser().parse(input)

    #expect(result.errors.isEmpty)
    #expect(result.variables.map(\.key) == ["DATABASE_URL", "PORT", "EMPTY"])
    #expect(result.variables.map(\.value) == ["postgres://localhost/app", "3000", ""])
  }

  @Test
  func parsesQuotesEscapesAndMultilineValues() {
    let input = #"""
      SINGLE='literal $HOME $(whoami) `uname` # text'
      DOUBLE="line one\nline two\t\"quoted\""
      MULTILINE="first
      second"
      UNKNOWN="keep\q"
      """#

    let result = DotenvParser().parse(input)

    #expect(result.errors.isEmpty)
    #expect(result.value(for: "SINGLE") == "literal $HOME $(whoami) `uname` # text")
    #expect(result.value(for: "DOUBLE") == "line one\nline two\t\"quoted\"")
    #expect(result.value(for: "MULTILINE") == "first\nsecond")
    #expect(result.value(for: "UNKNOWN") == #"keep\q"#)
  }

  @Test
  func keepsUnquotedExpansionCharactersLiteral() {
    let result = DotenvParser().parse("VALUE=$HOME/${USER}/$(whoami)/`uname`")

    #expect(result.errors.isEmpty)
    #expect(result.value(for: "VALUE") == "$HOME/${USER}/$(whoami)/`uname`")
  }

  @Test
  func finalDuplicateWinsAndProducesWarning() {
    let result = DotenvParser().parse("PORT=3000\nPORT=4000")

    #expect(result.errors.isEmpty)
    #expect(result.variables.count == 1)
    #expect(result.value(for: "PORT") == "4000")
    #expect(result.warnings.map(\.code) == [.duplicateKey])
    #expect(result.warnings.first?.line == 2)
  }

  @Test
  func reportsInvalidKeyNullByteAndUnterminatedQuote() {
    let input = "1BAD=value\nGOOD=ok\nNULL=bad\0value\nOPEN='value"

    let result = DotenvParser().parse(input)

    #expect(result.errors.map(\.code) == [.invalidKey, .nullByte, .unterminatedQuote])
    #expect(result.value(for: "GOOD") == "ok")
  }

  @Test
  func hashStartsCommentOnlyAfterWhitespace() {
    let input = "URL=https://example.test/#fragment\nTOKEN=abc # comment"

    let result = DotenvParser().parse(input)

    #expect(result.value(for: "URL") == "https://example.test/#fragment")
    #expect(result.value(for: "TOKEN") == "abc")
  }

  @Test
  func serializerRoundTripsRepresentativeValues() {
    let variables = [
      DotenvVariable(key: "EMPTY", value: "", sourceLine: 1),
      DotenvVariable(key: "PLAIN", value: "simple", sourceLine: 2),
      DotenvVariable(key: "SPACED", value: "hello world", sourceLine: 3),
      DotenvVariable(key: "HASH", value: "a # b", sourceLine: 4),
      DotenvVariable(key: "MULTILINE", value: "one\ntwo", sourceLine: 5),
      DotenvVariable(key: "QUOTE", value: "say \"hello\"", sourceLine: 6),
    ]

    let encoded = DotenvSerializer().serialize(variables)
    let decoded = DotenvParser().parse(encoded)

    #expect(decoded.errors.isEmpty)
    #expect(decoded.variables.map(\.key) == variables.map(\.key))
    #expect(decoded.variables.map(\.value) == variables.map(\.value))
  }
}
