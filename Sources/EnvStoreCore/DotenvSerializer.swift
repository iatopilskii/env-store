public struct DotenvSerializer: Sendable {
    public init() {}

    public func serialize(_ variables: [DotenvVariable]) -> String {
        variables
            .map { "\($0.key)=\(encoded($0.value))" }
            .joined(separator: "\n")
    }

    private func encoded(_ value: String) -> String {
        guard !value.isEmpty else {
            return ""
        }

        if value.allSatisfy(\.isSafeUnquotedDotenvCharacter) {
            return value
        }

        return "\"\(escaped(value))\""
    }

    private func escaped(_ value: String) -> String {
        var result = ""
        for character in value {
            switch character {
            case "\\": result.append("\\\\")
            case "\"": result.append("\\\"")
            case "\n": result.append("\\n")
            case "\r": result.append("\\r")
            case "\t": result.append("\\t")
            default: result.append(character)
            }
        }
        return result
    }
}

private extension Character {
    var isSafeUnquotedDotenvCharacter: Bool {
        isLetter || isNumber || "_./:@%+,-".contains(self)
    }
}
