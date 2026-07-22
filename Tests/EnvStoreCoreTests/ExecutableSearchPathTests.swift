import Testing

@testable import EnvStoreCore

struct ExecutableSearchPathTests {
  @Test
  func keepsOnlyUniqueStandardizedAbsoluteDirectories() {
    let directories = ExecutableSearchPath.normalized(
      from: "/opt/homebrew/bin:relative:/usr/local/../local/bin:/opt/homebrew/bin::/usr/bin"
    )

    #expect(directories == ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"])
  }

  @Test
  func usesSystemDefaultsWhenPathIsMissingOrHasNoAbsoluteDirectories() {
    #expect(ExecutableSearchPath.normalized(from: nil) == ExecutableSearchPath.systemDefaults)
    #expect(
      ExecutableSearchPath.normalized(from: "relative:also-relative")
        == ExecutableSearchPath.systemDefaults
    )
  }
}
