import CSQLite
import Foundation

final class SQLiteConnection {
  private var handle: OpaquePointer?

  init(url: URL) throws {
    var opened: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(url.path, &opened, flags, nil) == SQLITE_OK else {
      let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
      if let opened {
        sqlite3_close(opened)
      }
      throw EnvStoreStorageError.databaseFailure(message)
    }
    handle = opened
  }

  deinit {
    close()
  }

  func configure() throws {
    try execute("PRAGMA journal_mode = WAL")
    try execute("PRAGMA synchronous = FULL")
    try execute("PRAGMA foreign_keys = ON")
    try execute("PRAGMA secure_delete = ON")
  }

  func execute(_ sql: String) throws {
    guard let handle else {
      throw EnvStoreStorageError.databaseClosed
    }
    var errorPointer: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
      let message =
        errorPointer.map { String(cString: $0) }
        ?? String(cString: sqlite3_errmsg(handle))
      sqlite3_free(errorPointer)
      throw EnvStoreStorageError.databaseFailure(message)
    }
  }

  func prepare(_ sql: String) throws -> SQLiteStatement {
    guard let handle else {
      throw EnvStoreStorageError.databaseClosed
    }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else {
      throw EnvStoreStorageError.databaseFailure(String(cString: sqlite3_errmsg(handle)))
    }
    return SQLiteStatement(handle: handle, statement: statement)
  }

  func transaction<Result>(_ body: () throws -> Result) throws -> Result {
    try execute("BEGIN IMMEDIATE")
    do {
      let result = try body()
      try execute("COMMIT")
      return result
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  func checkpoint() {
    guard let handle else { return }
    sqlite3_wal_checkpoint_v2(handle, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
  }

  func close() {
    guard let handle else { return }
    checkpoint()
    sqlite3_close_v2(handle)
    self.handle = nil
  }
}

final class SQLiteStatement {
  private let database: OpaquePointer
  private let statement: OpaquePointer

  init(handle: OpaquePointer, statement: OpaquePointer) {
    database = handle
    self.statement = statement
  }

  deinit {
    sqlite3_finalize(statement)
  }

  func bind(_ value: String, at index: Int32) throws {
    let result = value.withCString { pointer in
      sqlite3_bind_text(statement, index, pointer, -1, Self.transientDestructor)
    }
    try check(result)
  }

  func bind(_ value: Int, at index: Int32) throws {
    try check(sqlite3_bind_int64(statement, index, sqlite3_int64(value)))
  }

  func bind(_ value: Data, at index: Int32) throws {
    let result = value.withUnsafeBytes { bytes in
      sqlite3_bind_blob(
        statement, index, bytes.baseAddress, Int32(bytes.count), Self.transientDestructor)
    }
    try check(result)
  }

  func step() throws -> Bool {
    let result = sqlite3_step(statement)
    if result == SQLITE_ROW {
      return true
    }
    guard result == SQLITE_DONE else {
      throw EnvStoreStorageError.databaseFailure(String(cString: sqlite3_errmsg(database)))
    }
    return false
  }

  func text(at index: Int32) throws -> String {
    guard let pointer = sqlite3_column_text(statement, index) else {
      throw EnvStoreStorageError.invalidStoredData
    }
    return String(cString: pointer)
  }

  func integer(at index: Int32) -> Int {
    Int(sqlite3_column_int64(statement, index))
  }

  func data(at index: Int32) -> Data {
    let count = Int(sqlite3_column_bytes(statement, index))
    guard count > 0, let pointer = sqlite3_column_blob(statement, index) else {
      return Data()
    }
    return Data(bytes: pointer, count: count)
  }

  private func check(_ result: Int32) throws {
    guard result == SQLITE_OK else {
      throw EnvStoreStorageError.databaseFailure(String(cString: sqlite3_errmsg(database)))
    }
  }

  private static var transientDestructor: sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  }
}
