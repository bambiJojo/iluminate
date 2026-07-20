import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct PlaybackProgressStoreTests {
    @Test
    func storesIndependentResumePositionsMostRecentFirst() throws {
        let suiteName = "PlaybackProgressStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var date = Date(timeIntervalSince1970: 1_000)
        let store = PlaybackProgressStore(defaults: defaults, now: { date })

        store.save(contentID: "first", kind: .session, title: "First", progress: 0.2, duration: 600)
        date = date.addingTimeInterval(60)
        store.save(contentID: "second", kind: .audio, title: "Second", progress: 0.6, duration: 900)

        #expect(store.snapshots.map(\.contentID) == ["second", "first"])
        #expect(store.snapshot(for: "first")?.progress == 0.2)
        #expect(PlaybackProgressStore(defaults: defaults).snapshots.count == 2)
    }

    @Test
    func completionClearsOnlyCompletedContent() throws {
        let suiteName = "PlaybackProgressStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PlaybackProgressStore(defaults: defaults)

        store.save(contentID: "first", kind: .session, title: "First", progress: 0.4, duration: 600)
        store.save(contentID: "second", kind: .audio, title: "Second", progress: 0.5, duration: 900)
        store.save(contentID: "first", kind: .session, title: "First", progress: 1, duration: 600)

        #expect(store.snapshot(for: "first") == nil)
        #expect(store.snapshot(for: "second") != nil)
    }
}
