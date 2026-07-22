import AppKit
import Darwin
import EnvStoreBrokerCore
import EnvStoreCrypto
import EnvStoreIPC
import EnvStoreStorage
@preconcurrency import Foundation

final class BrokerXPCHandler: NSObject, EnvStoreBrokerXPCProtocol {
  private let service: BrokerService

  init(service: BrokerService) {
    self.service = service
  }

  func perform(
    _ request: NSData,
    standardInput: FileHandle,
    standardOutput: FileHandle,
    standardError: FileHandle,
    withReply reply: @escaping (NSData) -> Void
  ) {
    let service = service
    let requestData = request as Data
    let replyBox = XPCReply(reply)
    let receivedIO = ProcessIO(
      standardInput: standardInput.fileDescriptor,
      standardOutput: standardOutput.fileDescriptor,
      standardError: standardError.fileDescriptor
    )
    guard let ioLease = try? ProcessIOLease(duplicating: receivedIO) else {
      let response = BrokerResponse(
        success: false,
        errorCode: .invalidRequest,
        message: "Terminal streams could not be attached"
      )
      replyBox.send(
        ((try? BrokerCodec.encode(response)) ?? Data()) as NSData
      )
      return
    }

    let execution = XPCRequestExecution(
      service: service,
      requestData: requestData,
      ioLease: ioLease,
      reply: replyBox
    )
    Task { await execution.perform() }
  }
}

private final class XPCRequestExecution: @unchecked Sendable {
  private let service: BrokerService
  private let requestData: Data
  private let ioLease: ProcessIOLease
  private let reply: XPCReply

  init(
    service: BrokerService,
    requestData: Data,
    ioLease: ProcessIOLease,
    reply: XPCReply
  ) {
    self.service = service
    self.requestData = requestData
    self.ioLease = ioLease
    self.reply = reply
  }

  func perform() async {
    let response: BrokerResponse
    do {
      let decoded = try BrokerCodec.decode(BrokerRequest.self, from: requestData)
      response = await service.handle(decoded, io: ioLease.io)
    } catch {
      response = BrokerResponse(
        success: false,
        errorCode: .invalidRequest,
        message: "Request could not be decoded"
      )
    }
    let data = (try? BrokerCodec.encode(response)) ?? Data()
    reply.send(data as NSData)
  }
}

private final class XPCReply: @unchecked Sendable {
  private let callback: (NSData) -> Void

  init(_ callback: @escaping (NSData) -> Void) {
    self.callback = callback
  }

  func send(_ data: NSData) {
    callback(data)
  }
}

private final class GrantInvalidationObserver {
  private let service: BrokerService
  private var workspaceTokens: [NSObjectProtocol] = []
  private var distributedTokens: [NSObjectProtocol] = []

  init(service: BrokerService) {
    self.service = service
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.willSleepNotification,
      NSWorkspace.sessionDidResignActiveNotification,
    ] {
      workspaceTokens.append(
        workspaceCenter.addObserver(forName: name, object: nil, queue: nil) { [service] _ in
          service.revokeAllGrants()
        }
      )
    }
    let distributedCenter = DistributedNotificationCenter.default()
    distributedTokens.append(
      distributedCenter.addObserver(
        forName: Notification.Name("com.apple.screenIsLocked"),
        object: nil,
        queue: nil
      ) { [service] _ in
        service.revokeAllGrants()
      }
    )
  }

  deinit {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceTokens.forEach(workspaceCenter.removeObserver)
    let distributedCenter = DistributedNotificationCenter.default()
    distributedTokens.forEach(distributedCenter.removeObserver)
  }
}

final class BrokerListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let handler: BrokerXPCHandler

  init(handler: BrokerXPCHandler) {
    self.handler = handler
  }

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    guard connection.effectiveUserIdentifier == geteuid() else {
      return false
    }
    connection.exportedInterface = NSXPCInterface(with: EnvStoreBrokerXPCProtocol.self)
    connection.exportedObject = handler
    connection.resume()
    return true
  }
}

enum EnvStoreBrokerMain {
  static func main() {
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    let databaseURL =
      applicationSupport
      .appending(path: "EnvStore", directoryHint: .isDirectory)
      .appending(path: "vault.sqlite")
    let service = BrokerService(
      storeProvider: {
        try? EncryptedVaultStore(
          databaseURL: databaseURL,
          rootKeyStore: KeychainRootKeyStore(),
          verifyRootKeyOnOpen: false,
          allowCreatingVault: false
        )
      },
      vaultAvailabilityProvider: {
        FileManager.default.fileExists(atPath: databaseURL.path)
      }
    )
    let invalidationObserver = GrantInvalidationObserver(service: service)
    let handler = BrokerXPCHandler(service: service)
    let delegate = BrokerListenerDelegate(handler: handler)
    let listener = NSXPCListener(machServiceName: EnvStoreIPC.machServiceName)
    listener.delegate = delegate
    listener.resume()
    withExtendedLifetime(invalidationObserver) {
      RunLoop.current.run()
    }
  }
}

EnvStoreBrokerMain.main()
