import Foundation

public struct ProjectBinding: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let path: String
  public let setID: UUID

  public init(id: UUID = UUID(), path: String, setID: UUID) {
    self.id = id
    self.path = path.standardizedAbsolutePath
    self.setID = setID
  }
}

public struct ProjectBindingResolver: Sendable {
  public init() {}

  public func resolve(workingDirectory: String, bindings: [ProjectBinding]) -> ProjectBinding? {
    let directoryComponents = workingDirectory.standardizedAbsolutePath.pathComponents

    return
      bindings
      .filter { $0.path.pathComponents.isPrefix(of: directoryComponents) }
      .max { $0.path.pathComponents.count < $1.path.pathComponents.count }
  }
}

extension String {
  public var standardizedAbsolutePath: String {
    URL(fileURLWithPath: self).standardizedFileURL.path
  }
}

extension String {
  fileprivate var pathComponents: [String] {
    URL(fileURLWithPath: self).pathComponents
  }
}

extension Array where Element: Equatable {
  fileprivate func isPrefix(of candidate: [Element]) -> Bool {
    count <= candidate.count && elementsEqual(candidate.prefix(count))
  }
}
