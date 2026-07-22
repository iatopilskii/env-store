import Foundation

public enum ExecutableSearchPath {
  public static let systemDefaults = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]

  public static func normalized(from path: String?) -> [String] {
    guard let path else { return systemDefaults }
    return normalized(directories: path.split(separator: ":").map(String.init))
  }

  public static func normalized(directories: [String]) -> [String] {
    var seen = Set<String>()
    let normalized = directories.compactMap { directory -> String? in
      guard directory.hasPrefix("/") else { return nil }
      let standardized = directory.standardizedAbsolutePath
      guard seen.insert(standardized).inserted else { return nil }
      return standardized
    }
    return normalized.isEmpty ? systemDefaults : normalized
  }
}
