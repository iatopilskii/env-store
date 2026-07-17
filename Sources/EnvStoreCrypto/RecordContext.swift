import Foundation

public enum RecordKind: String, Codable, Sendable {
    case profile
    case revisionSnapshot
    case setManifest
    case variableValue
    case wrappedSetKey
}

public struct RecordContext: Equatable, Sendable {
    public let vaultID: UUID
    public let recordID: UUID
    public let kind: RecordKind
    public let schemaVersion: Int

    public init(vaultID: UUID, recordID: UUID, kind: RecordKind, schemaVersion: Int) {
        self.vaultID = vaultID
        self.recordID = recordID
        self.kind = kind
        self.schemaVersion = schemaVersion
    }

    var authenticatedData: Data {
        Data(
            "envstore:v1|schema:\(schemaVersion)|vault:\(vaultID.uuidString.lowercased())|record:\(recordID.uuidString.lowercased())|kind:\(kind.rawValue)".utf8
        )
    }
}
