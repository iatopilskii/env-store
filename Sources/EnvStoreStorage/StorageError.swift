import Foundation

public enum EnvStoreStorageError: Error, Equatable, Sendable {
    case databaseClosed
    case databaseFailure(String)
    case invalidStoredData
    case setNotFound(UUID)
}
