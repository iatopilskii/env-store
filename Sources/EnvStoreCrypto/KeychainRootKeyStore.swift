import Foundation
import LocalAuthentication
import Security

public final class KeychainRootKeyStore: RootKeyStore, @unchecked Sendable {
  public enum Backend: Equatable, Sendable {
    case automatic
    case dataProtection
    case fileBased
  }

  private let service: String
  private let account: String
  private let backend: Backend
  private let contextFactory: @Sendable () -> LAContext

  public init(
    service: String = "dev.envstore.vault",
    account: String = "root-key",
    backend: Backend = .automatic,
    contextFactory: @escaping @Sendable () -> LAContext = LAContext.init
  ) {
    self.service = service
    self.account = account
    self.backend = Self.resolveBackend(
      backend,
      hasDataProtectionEntitlement: Self.hasDataProtectionEntitlement()
    )
    self.contextFactory = contextFactory
  }

  public func loadExisting(reason: String) throws -> VaultKey {
    switch backend {
    case .automatic:
      preconditionFailure("The automatic backend must be resolved during initialization.")
    case .dataProtection:
      return try loadDataProtectionKey(reason: reason)
    case .fileBased:
      try authenticateDeviceOwner(reason: reason)
      return try readExistingKey(authenticationContext: nil)
    }
  }

  public func createIfMissing(reason: String) throws -> VaultKey {
    switch backend {
    case .automatic:
      preconditionFailure("The automatic backend must be resolved during initialization.")
    case .dataProtection:
      return try createDataProtectionKeyIfMissing(reason: reason)
    case .fileBased:
      return try createFileBasedKeyIfMissing(reason: reason)
    }
  }

  static func resolveBackend(
    _ backend: Backend,
    hasDataProtectionEntitlement: Bool
  ) -> Backend {
    guard backend == .automatic else { return backend }
    return hasDataProtectionEntitlement ? .dataProtection : .fileBased
  }

  private func loadDataProtectionKey(reason: String) throws -> VaultKey {
    let context = authenticationContext(reason: reason)
    return try readExistingKey(authenticationContext: context)
  }

  private func createDataProtectionKeyIfMissing(reason: String) throws -> VaultKey {
    if itemExistsWithoutAuthentication() {
      return try loadDataProtectionKey(reason: reason)
    }

    let accessControl = try makeDataProtectionAccessControl()
    return try addGeneratedKey(
      additionalAttributes: [kSecAttrAccessControl as String: accessControl],
      duplicateReader: { try self.loadDataProtectionKey(reason: reason) }
    )
  }

  private func createFileBasedKeyIfMissing(reason: String) throws -> VaultKey {
    try authenticateDeviceOwner(reason: reason)
    if itemExistsWithoutAuthentication() {
      return try readExistingKey(authenticationContext: nil)
    }

    // Omitting kSecAttrAccess gives file-based Keychain its default ACL, which trusts only the
    // creating app for restricted operations. Other clients still require a system prompt.
    return try addGeneratedKey(
      additionalAttributes: [:],
      duplicateReader: { try self.readExistingKey(authenticationContext: nil) }
    )
  }

  private func addGeneratedKey(
    additionalAttributes: [String: Any],
    duplicateReader: () throws -> VaultKey
  ) throws -> VaultKey {
    let key = try VaultKey.random()
    var query = baseQuery
    for (name, value) in additionalAttributes {
      query[name] = value
    }
    query[kSecValueData as String] = key.withUnsafeBytes { bytes in
      Data(bytes: bytes.baseAddress!, count: bytes.count)
    }

    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
      return try duplicateReader()
    }
    guard status == errSecSuccess else {
      throw EnvStoreCryptoError.keychainFailure(status)
    }
    return key
  }

  private func readExistingKey(authenticationContext: LAContext?) throws -> VaultKey {
    var result: CFTypeRef?
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    if let authenticationContext {
      query[kSecUseAuthenticationContext as String] = authenticationContext
    }

    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      throw EnvStoreCryptoError.missingRootKey
    }
    guard status == errSecSuccess, let data = result as? Data else {
      throw EnvStoreCryptoError.keychainFailure(status)
    }
    return try VaultKey(bytes: data)
  }

  var baseQuery: [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if backend == .dataProtection {
      query[kSecAttrSynchronizable as String] = false
      query[kSecUseDataProtectionKeychain as String] = true
    }
    return query
  }

  private func itemExistsWithoutAuthentication() -> Bool {
    var query = baseQuery
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    if backend == .dataProtection {
      let context = contextFactory()
      context.interactionNotAllowed = true
      query[kSecUseAuthenticationContext as String] = context
    }
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess || status == errSecInteractionNotAllowed
  }

  private func makeDataProtectionAccessControl() throws -> SecAccessControl {
    var creationError: Unmanaged<CFError>?
    guard
      let accessControl = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        .userPresence,
        &creationError
      )
    else {
      let status =
        creationError.map {
          OSStatus(CFErrorGetCode($0.takeRetainedValue()))
        } ?? errSecParam
      throw EnvStoreCryptoError.keychainFailure(status)
    }
    return accessControl
  }

  private func authenticationContext(reason: String) -> LAContext {
    let context = contextFactory()
    context.touchIDAuthenticationAllowableReuseDuration = 0
    context.localizedReason = reason
    return context
  }

  private func authenticateDeviceOwner(reason: String) throws {
    let context = authenticationContext(reason: reason)
    let reply = LocalAuthenticationReply()
    let semaphore = DispatchSemaphore(value: 0)
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
      reply.complete(success: success, error: error)
      semaphore.signal()
    }
    semaphore.wait()
    try reply.get()
  }

  private static func hasDataProtectionEntitlement() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    let entitlementNames = [
      "com.apple.application-identifier",
      "keychain-access-groups",
      "com.apple.security.application-groups",
    ]
    return entitlementNames.contains { name in
      SecTaskCopyValueForEntitlement(task, name as CFString, nil) != nil
    }
  }

}

private final class LocalAuthenticationReply: @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<Void, EnvStoreCryptoError>?

  func complete(success: Bool, error: (any Error)?) {
    let completedResult: Result<Void, EnvStoreCryptoError> =
      success ? .success(()) : .failure(Self.map(error: error))
    lock.withLock {
      result = completedResult
    }
  }

  func get() throws {
    let completedResult = lock.withLock { result }
    guard let completedResult else {
      throw EnvStoreCryptoError.authenticationRejected
    }
    try completedResult.get()
  }

  private static func map(error: (any Error)?) -> EnvStoreCryptoError {
    let code = (error as NSError?)?.code
    let canceledCodes = [
      LAError.Code.userCancel.rawValue,
      LAError.Code.appCancel.rawValue,
      LAError.Code.systemCancel.rawValue,
    ]
    if let code, canceledCodes.contains(code) {
      return .authenticationCanceled
    }

    let unavailableCodes = [
      LAError.Code.biometryNotAvailable.rawValue,
      LAError.Code.biometryNotEnrolled.rawValue,
      LAError.Code.passcodeNotSet.rawValue,
      LAError.Code.notInteractive.rawValue,
    ]
    if let code, unavailableCodes.contains(code) {
      return .authenticationUnavailable
    }
    return .authenticationRejected
  }
}
