import Foundation

public struct EnvironmentVariable: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let key: String
    public let value: String

    public init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

public struct EnvironmentSetDraft: Codable, Equatable, Sendable {
    public let name: String
    public let note: String
    public let variables: [EnvironmentVariable]

    public init(name: String, note: String = "", variables: [EnvironmentVariable]) {
        self.name = name
        self.note = note
        self.variables = variables
    }
}

public struct EnvironmentSet: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let note: String
    public let variables: [EnvironmentVariable]
    public let revision: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        name: String,
        note: String,
        variables: [EnvironmentVariable],
        revision: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.variables = variables
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum EnvironmentSetValidationError: Error, Equatable, Sendable {
    case emptyName
    case duplicateVariableKey(String)
    case invalidVariableKey(String)
    case nullByte(String)
}

public extension EnvironmentSetDraft {
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnvironmentSetValidationError.emptyName
        }

        var seenKeys = Set<String>()
        for variable in variables {
            guard variable.key.isValidEnvironmentKey else {
                throw EnvironmentSetValidationError.invalidVariableKey(variable.key)
            }
            guard !variable.value.contains("\0") else {
                throw EnvironmentSetValidationError.nullByte(variable.key)
            }
            guard seenKeys.insert(variable.key).inserted else {
                throw EnvironmentSetValidationError.duplicateVariableKey(variable.key)
            }
        }
    }
}

private extension String {
    var isValidEnvironmentKey: Bool {
        let bytes = Array(utf8)
        guard let first = bytes.first, first.isEnvironmentKeyLetter || first == 95 else {
            return false
        }
        return bytes.dropFirst().allSatisfy {
            $0.isEnvironmentKeyLetter || (48...57).contains($0) || $0 == 95
        }
    }
}

private extension UInt8 {
    var isEnvironmentKeyLetter: Bool {
        (65...90).contains(self) || (97...122).contains(self)
    }
}
