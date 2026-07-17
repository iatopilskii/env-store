import Foundation
import Testing
@testable import EnvStoreCrypto

struct EnvelopeCipherTests {
    private let vaultID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let recordID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test
    func sealsAndOpensPayloadWithBoundContext() throws {
        let key = try VaultKey(bytes: Data(repeating: 0x11, count: 32))
        let context = recordContext(kind: .variableValue)
        let plaintext = Data("super-secret".utf8)

        let sealed = try EnvelopeCipher().seal(plaintext, using: key, context: context)
        let opened = try EnvelopeCipher().open(sealed, using: key, context: context)

        #expect(opened == plaintext)
        #expect(sealed.nonce.count == 12)
        #expect(sealed.tag.count == 16)
        #expect(sealed.ciphertext != plaintext)
    }

    @Test
    func randomNonceChangesCiphertext() throws {
        let key = try VaultKey(bytes: Data(repeating: 0x22, count: 32))
        let context = recordContext(kind: .setManifest)
        let plaintext = Data("same-value".utf8)

        let first = try EnvelopeCipher().seal(plaintext, using: key, context: context)
        let second = try EnvelopeCipher().seal(plaintext, using: key, context: context)

        #expect(first.nonce != second.nonce)
        #expect(first.ciphertext != second.ciphertext)
    }

    @Test
    func rejectsModifiedCiphertextTagAndContext() throws {
        let key = try VaultKey(bytes: Data(repeating: 0x33, count: 32))
        let context = recordContext(kind: .variableValue)
        let sealed = try EnvelopeCipher().seal(Data("secret".utf8), using: key, context: context)

        var changedCiphertext = sealed.ciphertext
        changedCiphertext[changedCiphertext.startIndex] ^= 0x01
        let tamperedPayload = SealedPayload(
            nonce: sealed.nonce,
            ciphertext: changedCiphertext,
            tag: sealed.tag
        )

        var changedTag = sealed.tag
        changedTag[changedTag.startIndex] ^= 0x01
        let tamperedTag = SealedPayload(
            nonce: sealed.nonce,
            ciphertext: sealed.ciphertext,
            tag: changedTag
        )

        let wrongContext = RecordContext(
            vaultID: vaultID,
            recordID: recordID,
            kind: .profile,
            schemaVersion: 1
        )

        #expect(throws: EnvStoreCryptoError.authenticationFailed) {
            try EnvelopeCipher().open(tamperedPayload, using: key, context: context)
        }
        #expect(throws: EnvStoreCryptoError.authenticationFailed) {
            try EnvelopeCipher().open(tamperedTag, using: key, context: context)
        }
        #expect(throws: EnvStoreCryptoError.authenticationFailed) {
            try EnvelopeCipher().open(sealed, using: key, context: wrongContext)
        }
    }

    @Test
    func wrapsDataKeyAndSupportsRootRotation() throws {
        let oldRoot = try VaultKey(bytes: Data(repeating: 0x44, count: 32))
        let newRoot = try VaultKey(bytes: Data(repeating: 0x55, count: 32))
        let dataKey = try VaultKey(bytes: Data(repeating: 0x66, count: 32))
        let context = recordContext(kind: .wrappedSetKey)
        let cipher = EnvelopeCipher()

        let oldEnvelope = try cipher.wrap(dataKey, using: oldRoot, context: context)
        let unwrapped = try cipher.unwrap(oldEnvelope, using: oldRoot, context: context)
        let newEnvelope = try cipher.wrap(unwrapped, using: newRoot, context: context)
        let rotated = try cipher.unwrap(newEnvelope, using: newRoot, context: context)

        #expect(rotated.bytesForTesting == dataKey.bytesForTesting)
        #expect(throws: EnvStoreCryptoError.authenticationFailed) {
            try cipher.unwrap(newEnvelope, using: oldRoot, context: context)
        }
    }

    @Test
    func rejectsKeysThatAreNotExactly256Bits() {
        #expect(throws: EnvStoreCryptoError.invalidKeyLength) {
            try VaultKey(bytes: Data(repeating: 0, count: 31))
        }
        #expect(throws: EnvStoreCryptoError.invalidKeyLength) {
            try VaultKey(bytes: Data(repeating: 0, count: 33))
        }
    }

    private func recordContext(kind: RecordKind) -> RecordContext {
        RecordContext(
            vaultID: vaultID,
            recordID: recordID,
            kind: kind,
            schemaVersion: 1
        )
    }
}

