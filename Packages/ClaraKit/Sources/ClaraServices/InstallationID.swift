import ClaraLegacy
import Foundation

/// Anonymous, stable installation ID, used only to assign the A/B group.
///
/// It lives in the legacy Objective-C storage. Note that we call
/// `loadValue(forKey:)` with `await`: Swift generated that `async` version
/// automatically from the completion-handler method.
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
