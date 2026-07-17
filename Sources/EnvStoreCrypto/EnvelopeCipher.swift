import CryptoKit
import Foundation

public struct SealedPayload: Codable, Equatable, Sendable {
    public let nonce: Data
    public let ciphertext: Data
    public let tag: Data

    public init(nonce: Data, ciphertext: Data, tag: Data) {
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

public struct EnvelopeCipher: Sendable {
    public init() {}

    public func seal(
        _ plaintext: Data,
        using key: VaultKey,
        context: RecordContext
    ) throws -> SealedPayload {
        let symmetricKey = key.withUnsafeBytes(SymmetricKey.init(data:))
        let sealed = try AES.GCM.seal(
            plaintext,
            using: symmetricKey,
            authenticating: context.authenticatedData
        )
        return SealedPayload(
            nonce: sealed.nonce.withUnsafeBytes { bytes in
                Data(bytes: bytes.baseAddress!, count: bytes.count)
            },
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
    }

    public func open(
        _ payload: SealedPayload,
        using key: VaultKey,
        context: RecordContext
    ) throws -> Data {
        do {
            let nonce = try AES.GCM.Nonce(data: payload.nonce)
            let sealed = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: payload.ciphertext,
                tag: payload.tag
            )
            let symmetricKey = key.withUnsafeBytes(SymmetricKey.init(data:))
            return try AES.GCM.open(
                sealed,
                using: symmetricKey,
                authenticating: context.authenticatedData
            )
        } catch {
            throw EnvStoreCryptoError.authenticationFailed
        }
    }

    public func wrap(
        _ key: VaultKey,
        using wrappingKey: VaultKey,
        context: RecordContext
    ) throws -> SealedPayload {
        try key.withUnsafeBytes { bytes in
            try seal(Data(bytes), using: wrappingKey, context: context)
        }
    }

    public func unwrap(
        _ payload: SealedPayload,
        using wrappingKey: VaultKey,
        context: RecordContext
    ) throws -> VaultKey {
        try VaultKey(bytes: open(payload, using: wrappingKey, context: context))
    }

    public func deriveDomainKey(
        from rootKey: VaultKey,
        vaultID: UUID,
        kind: RecordKind
    ) throws -> VaultKey {
        let inputKey = rootKey.withUnsafeBytes(SymmetricKey.init(data:))
        let salt = Data("envstore:v1:vault:\(vaultID.uuidString.lowercased())".utf8)
        let info = Data("envstore:v1:domain:\(kind.rawValue)".utf8)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: info,
            outputByteCount: VaultKey.byteCount
        )
        let bytes = derived.withUnsafeBytes { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count)
        }
        return try VaultKey(bytes: bytes)
    }
}
