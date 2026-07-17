import Testing
@testable import EnvStoreCore

struct EnvironmentKeyRiskTests {
    @Test(arguments: [
        ("PATH", EnvironmentKeyRisk.executableSearchPath),
        ("HOME", EnvironmentKeyRisk.identityContext),
        ("SHELL", EnvironmentKeyRisk.identityContext),
        ("DYLD_INSERT_LIBRARIES", EnvironmentKeyRisk.dynamicLoader),
        ("LD_PRELOAD", EnvironmentKeyRisk.dynamicLoader),
    ])
    func flagsDangerousKeys(key: String, expectedRisk: EnvironmentKeyRisk) {
        #expect(EnvironmentKeyRisk.classify(key) == expectedRisk)
    }

    @Test
    func acceptsOrdinaryApplicationKeys() {
        #expect(EnvironmentKeyRisk.classify("DATABASE_URL") == nil)
        #expect(EnvironmentKeyRisk.classify("API_TOKEN") == nil)
    }
}

