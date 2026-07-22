import Foundation

public struct ShellPathAdvisor: Equatable, Sendable {
  public let cliDirectory: URL
  public let isCLIDirectoryInPath: Bool

  public init(homeDirectory: URL, pathEnvironment: String) {
    cliDirectory = homeDirectory.appending(path: ".local/bin", directoryHint: .isDirectory)
    let expectedPath = cliDirectory.standardizedFileURL.path
    isCLIDirectoryInPath =
      pathEnvironment
      .split(separator: ":", omittingEmptySubsequences: true)
      .contains { URL(filePath: String($0)).standardizedFileURL.path == expectedPath }
  }

  public var shouldShowNotice: Bool {
    !isCLIDirectoryInPath
  }

  public var zshSetupCommand: String {
    #"grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null || printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc""#
  }
}
