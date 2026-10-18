import ClaraLegacy
import Foundation

/// ID anônimo e estável da instalação, usado só para sortear o grupo do A/B.
///
/// Fica no armazenamento legado em Objective-C. Repare que chamamos
/// `loadValue(forKey:)` com `await`: o Swift gerou essa versão `async`
/// automaticamente a partir do método com completion handler.
public struct InstallationIDProvider: Sendable {
    private static let key = "installation-id"
    private let store: CLALegacyKeyValueStore

    public init(store: CLALegacyKeyValueStore = .shared) {
        self.store = store
    }

    public func installationID() async -> String {
        if let existing = await store.loadValue(forKey: Self.key) {
            return existing
        }
        let created = UUID().uuidString
        await store.saveValue(created, forKey: Self.key)
        return created
    }
}
