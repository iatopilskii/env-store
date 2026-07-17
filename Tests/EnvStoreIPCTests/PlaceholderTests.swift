import Testing
@testable import EnvStoreIPC

@Test
func ipcTargetLoads() {
    #expect(EnvStoreIPC.protocolVersion == 1)
}
