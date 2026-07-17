import Foundation

public enum EnvStoreCryptoError: Error, Equatable, Sendable {
  case authenticationFailed
  case invalidKeyLength
  case invalidPayload
  case keyGenerationFailed(OSStatus)
  case keychainFailure(OSStatus)
  case missingRootKey
}
