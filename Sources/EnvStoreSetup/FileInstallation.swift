import Darwin
import Foundation

enum FileInstallation {
  static func validateSkill(at url: URL) throws {
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue,
      FileManager.default.fileExists(atPath: url.appending(path: "SKILL.md").path)
    else {
      throw EnvStoreSetupError.invalidBundledResource(url.path)
    }
  }

  static func ensureSafeDestination(_ destination: URL, below homeDirectory: URL) throws {
    let standardizedHome = homeDirectory.standardizedFileURL
    let standardizedDestination = destination.standardizedFileURL
    let homeComponents = standardizedHome.pathComponents
    let destinationComponents = standardizedDestination.pathComponents
    guard
      destinationComponents.count > homeComponents.count,
      Array(destinationComponents.prefix(homeComponents.count)) == homeComponents
    else {
      throw EnvStoreSetupError.unsafeDestination(destination.path)
    }

    var current = standardizedHome
    for component in destinationComponents.dropFirst(homeComponents.count) {
      current.append(path: component)
      guard FileManager.default.fileExists(atPath: current.path) else { continue }
      if isSymbolicLink(current) {
        throw EnvStoreSetupError.unsafeDestination(current.path)
      }
    }
  }

  static func isSymbolicLink(_ url: URL) -> Bool {
    var information = stat()
    guard lstat(url.path, &information) == 0 else { return false }
    return information.st_mode & S_IFMT == S_IFLNK
  }

  static func atomicallyInstallFile(from source: URL, to destination: URL, mode: Int) throws {
    let fileManager = FileManager.default
    let directory = destination.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let staging = directory.appending(
      path: ".\(destination.lastPathComponent).staging-\(UUID().uuidString)")
    defer { try? fileManager.removeItem(at: staging) }
    try fileManager.copyItem(at: source, to: staging)
    try fileManager.setAttributes([.posixPermissions: mode], ofItemAtPath: staging.path)
    if fileManager.fileExists(atPath: destination.path) {
      if isSymbolicLink(destination) {
        throw EnvStoreSetupError.unsafeDestination(destination.path)
      }
      _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
    } else {
      try fileManager.moveItem(at: staging, to: destination)
    }
  }
}
