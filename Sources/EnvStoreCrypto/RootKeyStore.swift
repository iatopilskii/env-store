import Foundation

public protocol RootKeyStore: Sendable {
  func loadExisting(reason: String) throws -> VaultKey
  func createIfMissing(reason: String) throws -> VaultKey
}

public final class InMemoryRootKeyStore: RootKeyStore, @unchecked Sendable {
  private let lock = NSLock()
  private var key: VaultKey?

  public init() {}

  public var hasKey: Bool {
    lock.withLock { key != nil }
  }

  public func loadExisting(reason _: String) throws -> VaultKey {
    try lock.withLock {
      guard let key else {
        throw EnvStoreCryptoError.missingRootKey
      }
      return key
    }
  }

  public func createIfMissing(reason _: String) throws -> VaultKey {
    try lock.withLock {
      if let key {
        return key
      }
      let generated = try VaultKey.random()
      key = generated
      return generated
    }
  }
}
