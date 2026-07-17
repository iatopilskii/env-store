@preconcurrency import Foundation

public enum BrokerTransportError: Error, Equatable, Sendable {
  case connectionFailed
  case invalidResponse
  case timedOut
}

public protocol BrokerTransport: Sendable {
  func send(
    _ request: BrokerRequest,
    standardInput: FileHandle,
    standardOutput: FileHandle,
    standardError: FileHandle
  ) throws -> BrokerResponse
}

public final class XPCBrokerTransport: BrokerTransport, @unchecked Sendable {
  private let serviceName: String
  private let timeout: TimeInterval

  public init(
    serviceName: String = EnvStoreIPC.machServiceName,
    timeout: TimeInterval = 120
  ) {
    self.serviceName = serviceName
    self.timeout = timeout
  }

  public func send(
    _ request: BrokerRequest,
    standardInput: FileHandle = .standardInput,
    standardOutput: FileHandle = .standardOutput,
    standardError: FileHandle = .standardError
  ) throws -> BrokerResponse {
    let requestData = try BrokerCodec.encode(request)
    let connection = NSXPCConnection(machServiceName: serviceName)
    connection.remoteObjectInterface = NSXPCInterface(with: EnvStoreBrokerXPCProtocol.self)
    let box = SynchronousResponseBox()
    connection.resume()
    defer { connection.invalidate() }

    let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
      box.resolve(.failure(.connectionFailed))
    }
    guard let broker = proxy as? EnvStoreBrokerXPCProtocol else {
      throw BrokerTransportError.connectionFailed
    }
    broker.perform(
      requestData as NSData,
      standardInput: standardInput,
      standardOutput: standardOutput,
      standardError: standardError
    ) { responseData in
      do {
        let response = try BrokerCodec.decode(BrokerResponse.self, from: responseData as Data)
        box.resolve(.success(response))
      } catch {
        box.resolve(.failure(.invalidResponse))
      }
    }
    return try box.wait(timeout: timeout).get()
  }
}

private final class SynchronousResponseBox: @unchecked Sendable {
  private let condition = NSCondition()
  private var result: Result<BrokerResponse, BrokerTransportError>?

  func resolve(_ result: Result<BrokerResponse, BrokerTransportError>) {
    condition.lock()
    if self.result == nil {
      self.result = result
      condition.broadcast()
    }
    condition.unlock()
  }

  func wait(timeout: TimeInterval) -> Result<BrokerResponse, BrokerTransportError> {
    condition.lock()
    defer { condition.unlock() }
    let deadline = Date().addingTimeInterval(timeout)
    while result == nil {
      guard condition.wait(until: deadline) else {
        return .failure(.timedOut)
      }
    }
    return result!
  }
}
