import Darwin
import Foundation
import Security

final class SecureBytes: @unchecked Sendable {
  private let storage: UnsafeMutableRawBufferPointer

  init(copying bytes: Data) {
    storage = UnsafeMutableRawBufferPointer.allocate(
      byteCount: bytes.count,
      alignment: MemoryLayout<UInt64>.alignment
    )
    _ = bytes.copyBytes(to: storage.bindMemory(to: UInt8.self))
    _ = mlock(storage.baseAddress, storage.count)
  }

  deinit {
    _ = memset_s(storage.baseAddress, storage.count, 0, storage.count)
    _ = munlock(storage.baseAddress, storage.count)
    storage.deallocate()
  }

  func withUnsafeBytes<Result>(
    _ body: (UnsafeRawBufferPointer) throws -> Result
  ) rethrows -> Result {
    try body(UnsafeRawBufferPointer(storage))
  }
}

public struct VaultKey: Sendable {
  public static let byteCount = 32

  private let storage: SecureBytes

  public init(bytes: Data) throws {
    guard bytes.count == Self.byteCount else {
      throw EnvStoreCryptoError.invalidKeyLength
    }
    storage = SecureBytes(copying: bytes)
  }

  public static func random() throws -> VaultKey {
    var bytes = Data(count: byteCount)
    let status = bytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
    }
    guard status == errSecSuccess else {
      throw EnvStoreCryptoError.keyGenerationFailed(status)
    }
    return try VaultKey(bytes: bytes)
  }

  func withUnsafeBytes<Result>(
    _ body: (UnsafeRawBufferPointer) throws -> Result
  ) rethrows -> Result {
    try storage.withUnsafeBytes(body)
  }

  var bytesForTesting: Data {
    storage.withUnsafeBytes { bytes in
      Data(bytes: bytes.baseAddress!, count: bytes.count)
    }
  }
}
