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
        let io = ProcessIO(
            standardInput: standardInput.fileDescriptor,
            standardOutput: standardOutput.fileDescriptor,
            standardError: standardError.fileDescriptor
        )
        let replyBox = XPCReply(reply)
        Task {
            let response: BrokerResponse
            do {
                let decoded = try BrokerCodec.decode(BrokerRequest.self, from: requestData)
                response = await service.handle(decoded, io: io)
            } catch {
                response = BrokerResponse(
                    success: false,
                    errorCode: .invalidRequest,
                    message: "Request could not be decoded"
                )
            }
            let data = (try? BrokerCodec.encode(response)) ?? Data()
            replyBox.send(data as NSData)
        }
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
        let databaseURL = applicationSupport
            .appending(path: "EnvStore", directoryHint: .isDirectory)
            .appending(path: "vault.sqlite")
        let vaultAvailable = FileManager.default.fileExists(atPath: databaseURL.path)
        let store = try? EncryptedVaultStore(
            databaseURL: databaseURL,
            rootKeyStore: KeychainRootKeyStore(),
            verifyRootKeyOnOpen: false,
            allowCreatingVault: false
        )
        let service = BrokerService(store: store, vaultAvailable: vaultAvailable)
        let handler = BrokerXPCHandler(service: service)
        let delegate = BrokerListenerDelegate(handler: handler)
        let listener = NSXPCListener(machServiceName: EnvStoreIPC.machServiceName)
        listener.delegate = delegate
        listener.resume()
        RunLoop.current.run()
    }
}

EnvStoreBrokerMain.main()
