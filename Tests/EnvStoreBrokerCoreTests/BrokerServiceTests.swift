import EnvStoreIPC
import Foundation
import Testing

@testable import EnvStoreBrokerCore

struct BrokerServiceTests {
  @Test
  func doctorReflectsVaultCreatedAfterBrokerStartup() async {
    let availability = AvailabilityBox()
    let service = BrokerService(
      storeProvider: { nil },
      vaultAvailabilityProvider: { availability.value }
    )

    let before = await service.handle(BrokerRequest(operation: .doctor))
    availability.value = true
    let after = await service.handle(BrokerRequest(operation: .doctor))

    #expect(before.message == "Broker is available; vault is not initialized")
    #expect(after.message == "Broker and vault are available")
  }
}

private final class AvailabilityBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue = false

  var value: Bool {
    get { lock.withLock { storedValue } }
    set { lock.withLock { storedValue = newValue } }
  }
}
