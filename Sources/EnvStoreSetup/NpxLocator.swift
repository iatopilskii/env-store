import Foundation

public struct NpxLocator: Sendable {
  private let systemSearchDirectories: [URL]

  public init() {
    systemSearchDirectories = [
      URL(filePath: "/opt/homebrew/bin", directoryHint: .isDirectory),
      URL(filePath: "/usr/local/bin", directoryHint: .isDirectory),
    ]
  }

  init(systemSearchDirectories: [URL]) {
    self.systemSearchDirectories = systemSearchDirectories
  }

  public func locate(homeDirectory: URL, pathEnvironment: String) -> URL? {
    candidates(homeDirectory: homeDirectory, pathEnvironment: pathEnvironment)
      .first { FileManager.default.isExecutableFile(atPath: $0.path) }
  }

  public func controlledPath(homeDirectory: URL, npxURL: URL) -> String {
    let directories = [
      npxURL.deletingLastPathComponent().path,
      homeDirectory.appending(path: ".local/bin").path,
      homeDirectory.appending(path: ".volta/bin").path,
      homeDirectory.appending(path: ".asdf/shims").path,
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      "/usr/sbin",
      "/sbin",
    ]
    return uniqueURLs(directories.map { URL(filePath: $0) }).map(\.path).joined(separator: ":")
  }

  private func candidates(homeDirectory: URL, pathEnvironment: String) -> [URL] {
    var urls = pathEnvironment.split(separator: ":", omittingEmptySubsequences: true)
      .map { URL(filePath: String($0)).appending(path: "npx") }
    urls += systemSearchDirectories.map { $0.appending(path: "npx") }
    urls += [
      homeDirectory.appending(path: ".volta/bin/npx"),
      homeDirectory.appending(path: ".asdf/shims/npx"),
      homeDirectory.appending(path: ".local/share/fnm/current/bin/npx"),
    ]
    urls += versionedExecutables(
      below: homeDirectory.appending(path: ".nvm/versions/node"),
      suffix: "bin/npx"
    )
    urls += versionedExecutables(
      below: homeDirectory.appending(path: ".local/share/fnm/node-versions"),
      suffix: "installation/bin/npx"
    )
    return uniqueURLs(urls)
  }

  private func versionedExecutables(below root: URL, suffix: String) -> [URL] {
    let children =
      (try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
      )) ?? []
    return children.sorted { $0.lastPathComponent > $1.lastPathComponent }
      .map { $0.appending(path: suffix) }
  }

  private func uniqueURLs(_ urls: [URL]) -> [URL] {
    var seen: Set<String> = []
    return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
  }
}
