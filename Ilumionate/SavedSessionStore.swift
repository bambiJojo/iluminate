import Foundation
import Observation

@MainActor
@Observable
final class SavedSessionStore {
    static let shared = SavedSessionStore()
    static let storageKey = "savedSessionIDs_v1"

    private(set) var sessionIDs: Set<String>
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sessionIDs = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    func contains(_ sessionID: String) -> Bool {
        sessionIDs.contains(sessionID)
    }

    func save(_ sessionID: String) {
        sessionIDs.insert(sessionID)
        persist()
    }

    func remove(_ sessionID: String) {
        sessionIDs.remove(sessionID)
        persist()
    }

    private func persist() {
        defaults.set(sessionIDs.sorted(), forKey: Self.storageKey)
    }
}
