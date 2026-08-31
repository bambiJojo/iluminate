//
//  PortalRecommenderTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

struct PortalRecommenderTests {

    @Test("Evening hours recommend a calming category")
    func eveningRecommendsCalm() {
        #expect(PortalRecommender.category(forHour: 22) == .sleep)
        #expect(PortalRecommender.category(forHour: 23) == .sleep)
    }

    @Test("Late night recommends sleep")
    func lateNightRecommendsSleep() {
        #expect(PortalRecommender.category(forHour: 1) == .sleep)
    }

    @Test("Morning recommends energy")
    func morningRecommendsEnergy() {
        #expect(PortalRecommender.category(forHour: 7) == .energy)
        #expect(PortalRecommender.category(forHour: 9) == .energy)
    }

    @Test("Midday recommends focus")
    func middayRecommendsFocus() {
        #expect(PortalRecommender.category(forHour: 13) == .focus)
    }

    @Test("Late afternoon/early evening recommends relax")
    func eveningRelax() {
        #expect(PortalRecommender.category(forHour: 18) == .relax)
    }

    @Test("Picks the first session whose first moment falls in the category range")
    func picksMatchingSession() {
        let sleepy = LightSession(
            session_name: "Delta Drift", duration_sec: 600,
            light_score: [LightMoment(time: 0, frequency: 0.75, intensity: 0.5, waveform: .sine)]
        )
        let focusy = LightSession(
            session_name: "Alpha Focus", duration_sec: 600,
            light_score: [LightMoment(time: 0, frequency: 1.75, intensity: 0.5, waveform: .sine)]
        )
        let pick = PortalRecommender.recommend(from: [focusy, sleepy], forHour: 23)
        #expect(pick?.session_name == "Delta Drift")
    }

    @Test("Falls back to the first session when none match the category")
    func fallsBackToFirst() {
        let only = LightSession(
            session_name: "Only One", duration_sec: 600,
            light_score: [LightMoment(time: 0, frequency: 10.0, intensity: 0.5, waveform: .sine)]
        )
        let pick = PortalRecommender.recommend(from: [only], forHour: 23)
        #expect(pick?.session_name == "Only One")
    }

    @Test("Returns nil for an empty library")
    func emptyLibraryReturnsNil() {
        #expect(PortalRecommender.recommend(from: [], forHour: 12) == nil)
    }
}
