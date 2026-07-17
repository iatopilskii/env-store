import Foundation

public enum EnvStoreStorageError: Error, Equatable, Sendable {
    case databaseClosed
    case databaseFailure(String)
    case invalidStoredData
    case projectNotLinked
    case profileNotFound
    case setNotFound(UUID)
    case vaultNotFound
}
