//
//  VisualFieldStoreTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct VisualFieldStoreTests {

    /// A defaults suite of its own per test, so tests never see each other's writes.
    private func freshDefaults() -> UserDefaults {
        let name = "VisualFieldStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("An empty store starts from the standard settings")
    func emptyStoreUsesDefaults() {
        let store = VisualFieldStore(defaults: freshDefaults())
        #expect(store.settings == VisualFieldSettings.standard)
    }

    @Test("Settings survive a round trip through the defaults")
    func settingsPersist() {
        let defaults = freshDefaults()
        let store = VisualFieldStore(defaults: defaults)

        var edited = VisualFieldSettings.standard
        edited.visual = .tunnel
        edited.direction = .outward
        edited.tint = .custom("FF8800")
        edited.duration = 600
        store.settings = edited

        #expect(VisualFieldStore(defaults: defaults).settings == edited)
    }

    @Test("Corrupt stored data degrades to the defaults instead of crashing")
    func corruptDataDegrades() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: VisualFieldStore.defaultsKey)
        #expect(VisualFieldStore(defaults: defaults).settings == VisualFieldSettings.standard)
    }

    @Test("A partial payload keeps the fields it has and defaults the rest")
    func partialPayloadFallsBackPerField() {
        let defaults = freshDefaults()
        defaults.set(Data(#"{"visual":"moire"}"#.utf8), forKey: VisualFieldStore.defaultsKey)

        let store = VisualFieldStore(defaults: defaults)
        #expect(store.settings.visual == .moire)
        #expect(store.settings.tint == VisualFieldSettings.standard.tint)
        #expect(store.settings.speed == VisualFieldSettings.standard.speed)
    }

    @Test("An unknown effect degrades to the default rather than losing every other field")
    func unknownEffectDegrades() {
        let defaults = freshDefaults()
        defaults.set(
            Data(#"{"visual":"kaleidoscope","direction":"outward"}"#.utf8),
            forKey: VisualFieldStore.defaultsKey
        )

        let store = VisualFieldStore(defaults: defaults)
        #expect(store.settings.visual == VisualFieldSettings.standard.visual)
        #expect(store.settings.direction == .outward)
    }

    @Test("Two stores on separate suites do not see each other")
    func storesAreIsolatedBySuite() {
        let a = VisualFieldStore(defaults: freshDefaults())
        let b = VisualFieldStore(defaults: freshDefaults())

        var edited = VisualFieldSettings.standard
        edited.visual = .glass
        a.settings = edited

        #expect(b.settings.visual == VisualFieldSettings.standard.visual)
    }

    @Test("Every mutation persists, not just the first")
    func repeatedMutationsPersist() {
        let defaults = freshDefaults()
        let store = VisualFieldStore(defaults: defaults)

        for visual in [TranceVisual.tunnel, .moire, .linescape] {
            var edited = store.settings
            edited.visual = visual
            store.settings = edited
        }

        #expect(VisualFieldStore(defaults: defaults).settings.visual == .linescape)
    }
}
