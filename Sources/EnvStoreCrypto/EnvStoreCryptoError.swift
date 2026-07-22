import Foundation

public enum EnvStoreCryptoError: Error, Equatable, Sendable {
  case authenticationCanceled
  case authenticationFailed
  case authenticationRejected
  case authenticationUnavailable
  case invalidKeyLength
  case invalidPayload
  case keyGenerationFailed(OSStatus)
  case keychainFailure(OSStatus)
  case missingRootKey
}
