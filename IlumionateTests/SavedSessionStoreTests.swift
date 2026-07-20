import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct SavedSessionStoreTests {
    @Test
    func savedSessionsPersistAndCanBeRemoved() throws {
        let suiteName = "SavedSessionStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SavedSessionStore(defaults: defaults)
        store.save("session-1")

        #expect(store.contains("session-1"))
        #expect(SavedSessionStore(defaults: defaults).contains("session-1"))

        store.remove("session-1")
        #expect(store.contains("session-1") == false)
    }
}
