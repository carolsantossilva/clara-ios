import ClaraLegacy
import Foundation
import Testing
@testable import ClaraServices

/// Uses the real legacy store, in a UserDefaults suite owned by the test.
@Suite("Installation ID")
struct InstallationIDTests {
    let suiteName = "clara-tests-\(UUID().uuidString)"

    @Test("creates the ID the first time and returns the same one afterwards")
    func createsOnceThenReuses() async {
        let store = CLALegacyKeyValueStore(suiteName: suiteName)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let first = await InstallationIDProvider(store: store).installationID()
        let second = await InstallationIDProvider(store: store).installationID()

        #expect(UUID(uuidString: first) != nil)
        #expect(second == first)
    }

    @Test("reads the ID the old app had already stored")
    func readsExistingValue() async {
        let store = CLALegacyKeyValueStore(suiteName: suiteName)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        await store.saveValue("instalacao-antiga", forKey: "installation-id")

        #expect(await InstallationIDProvider(store: store).installationID() == "instalacao-antiga")
    }
}
