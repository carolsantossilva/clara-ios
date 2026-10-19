import ClaraLegacy
import Foundation
import Testing
@testable import ClaraServices

/// Usa o armazenamento legado de verdade, numa suíte de UserDefaults só do teste.
@Suite("ID da instalação")
struct InstallationIDTests {
    let suiteName = "clara-tests-\(UUID().uuidString)"

    @Test("cria o ID na primeira vez e devolve o mesmo depois")
    func createsOnceThenReuses() async {
        let store = CLALegacyKeyValueStore(suiteName: suiteName)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let first = await InstallationIDProvider(store: store).installationID()
        let second = await InstallationIDProvider(store: store).installationID()

        #expect(UUID(uuidString: first) != nil)
        #expect(second == first)
    }

    @Test("lê o ID que o app antigo já tinha gravado")
    func readsExistingValue() async {
        let store = CLALegacyKeyValueStore(suiteName: suiteName)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        await store.saveValue("instalacao-antiga", forKey: "installation-id")

        #expect(await InstallationIDProvider(store: store).installationID() == "instalacao-antiga")
    }
}
