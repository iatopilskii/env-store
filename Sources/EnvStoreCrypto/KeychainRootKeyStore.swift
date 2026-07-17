import Foundation
import LocalAuthentication
import Security

public final class KeychainRootKeyStore: RootKeyStore, @unchecked Sendable {
  private let service: String
  private let account: String
  private let contextFactory: @Sendable () -> LAContext

  public init(
    service: String = "dev.envstore.vault",
    account: String = "root-key",
    contextFactory: @escaping @Sendable () -> LAContext = LAContext.init
  ) {
    self.service = service
    self.account = account
    self.contextFactory = contextFactory
  }

  public func loadExisting(reason: String) throws -> VaultKey {
    let context = contextFactory()
    context.touchIDAuthenticationAllowableReuseDuration = 0
    context.localizedReason = reason

    var result: CFTypeRef?
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context

    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      throw EnvStoreCryptoError.missingRootKey
    }
    guard status == errSecSuccess, let data = result as? Data else {
      throw EnvStoreCryptoError.keychainFailure(status)
    }
    return try VaultKey(bytes: data)
  }

  public func createIfMissing(reason: String) throws -> VaultKey {
    if itemExistsWithoutAuthentication() {
      return try loadExisting(reason: reason)
    }

    let key = try VaultKey.random()
    var accessControlError: Unmanaged<CFError>?
    guard
      let accessControl = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        .userPresence,
        &accessControlError
      )
    else {
      let status =
        accessControlError.map {
          OSStatus(CFErrorGetCode($0.takeRetainedValue()))
        } ?? errSecParam
      throw EnvStoreCryptoError.keychainFailure(status)
    }

    var query = baseQuery
    query[kSecAttrAccessControl as String] = accessControl
    query[kSecValueData as String] = key.withUnsafeBytes { bytes in
      Data(bytes: bytes.baseAddress!, count: bytes.count)
    }

    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
      return try loadExisting(reason: reason)
    }
    guard status == errSecSuccess else {
      throw EnvStoreCryptoError.keychainFailure(status)
    }
    return key
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }

  private func itemExistsWithoutAuthentication() -> Bool {
    var query = baseQuery
    let context = contextFactory()
    context.interactionNotAllowed = true
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess || status == errSecInteractionNotAllowed
  }
}
