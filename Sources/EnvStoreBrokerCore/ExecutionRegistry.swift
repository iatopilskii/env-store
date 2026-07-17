import Darwin
import Foundation

public final class ExecutionRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var processIDs: [UUID: pid_t] = [:]

  public init() {}

  public func register(executionID: UUID, processID: pid_t) {
    lock.withLock { processIDs[executionID] = processID }
  }

  public func unregister(executionID: UUID) {
    _ = lock.withLock { processIDs.removeValue(forKey: executionID) }
  }

  public func forward(signal: Int32, to executionID: UUID) -> Bool {
    guard (1...31).contains(signal),
      let processID = lock.withLock({ processIDs[executionID] })
    else {
      return false
    }
    if Darwin.kill(-processID, signal) == 0 {
      return true
    }
    return Darwin.kill(processID, signal) == 0
  }
}
