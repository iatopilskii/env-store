import Foundation
import Testing
@testable import EnvStoreIPC

struct BrokerProtocolTests {
    @Test
    func roundTripsExactRunRequest() throws {
        let payload = RunCommandPayload(
            setName: "Production",
            workingDirectory: "/tmp/project/../project",
            executablePath: "/usr/bin/printenv",
            arguments: ["API_TOKEN"]
        )
        let request = BrokerRequest(operation: .run, run: payload)

        let decoded = try BrokerCodec.decode(
            BrokerRequest.self,
            from: BrokerCodec.encode(request)
        )

        #expect(decoded == request)
        #expect(decoded.run?.workingDirectory == "/tmp/project")
    }

    @Test
    func rejectsUnknownProtocolBeforeDispatch() {
        let request = BrokerRequest(protocolVersion: 999, operation: .doctor)
        #expect(request.protocolVersion != EnvStoreIPC.protocolVersion)
    }

    @Test
    func responseNeverNeedsSecretFields() throws {
        let context = BrokerContext(
            vaultAvailable: true,
            setNames: ["Development"],
            activeGrantCount: 1
        )
        let data = try BrokerCodec.encode(BrokerResponse(success: true, context: context))
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.localizedCaseInsensitiveContains("value"))
        #expect(!json.localizedCaseInsensitiveContains("secret"))
    }
}
