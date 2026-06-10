//  PhaseOrderingRegressionTests.swift
//  IlumionateTests
//
//  Regression guard for the enforcePhaseOrdering ratchet defect: a transient
//  high-order phase blip in the resolved timeline must not ratchet the ordering
//  floor and erase a long, correctly-detected lower-order phase. The fix denoises
//  (majority-vote smooth + short-run collapse) BEFORE enforcing phase ordering.
//
import Testing
import Foundation
import CorpusKit
@testable import Ilumionate

@MainActor
struct PhaseOrderingRegressionTests {

    @Test("A transient blip does not erase the deepening phase (pre-adapt timeline)")
    func deepeningSurvivesTransientBlip() {
        let kase = ((try? CorpusLoader.load(subdirectory: "fixtures")) ?? [])
            .first { $0.id == "timeline-induction-deepening" }
        guard let kase else { Issue.record("timeline-induction-deepening fixture missing"); return }

        let analyzer = HypnosisPhaseAnalyzer()
        let words = analyzer.approximateWordTimestamps(from: kase.transcriptionSegments)
        // Pre-adapt consolidate path: isolates the resolve→order→smooth→collapse
        // pipeline from boundary refinement (a separate, untouched defect).
        let segments = analyzer.analyze(wordTimestamps: words, duration: kase.duration)
        let phases = Set(segments.map(\.phase))
        let rendered = segments.map { "\($0.phase.rawValue)@\(Int($0.startTime))-\(Int($0.endTime))" }

        // Truth is induction → deepening, with no therapeutic content anywhere.
        #expect(phases.contains(.deepening), "deepening was erased; got \(rendered)")
        #expect(!phases.contains(.therapy), "spurious therapy introduced by the ordering ratchet; got \(rendered)")
    }

    @Test("Final adapted output is non-overlapping and keeps deepening (rejects malformed proposal)")
    func finalAdaptedOutputIsValid() {
        let kase = ((try? CorpusLoader.load(subdirectory: "fixtures")) ?? [])
            .first { $0.id == "timeline-induction-deepening" }
        guard let kase else { Issue.record("timeline-induction-deepening fixture missing"); return }

        let analyzer = HypnosisPhaseAnalyzer()
        let transcription = AudioTranscriptionResult(
            fullText: kase.transcriptText, segments: kase.transcriptionSegments,
            duration: kase.duration, detectedLanguage: "en"
        )
        // Full pipeline including adaptPredictedPhases (the proposal/selection stage).
        let segments = analyzer.analyzeTranscription(transcription)
        let rendered = segments.map { "\($0.phase.rawValue)@\(Int($0.startTime))-\(Int($0.endTime))" }
        let sorted = segments.sorted { $0.startTime < $1.startTime }

        // A selected timeline must never contain overlapping spans.
        for (lhs, rhs) in zip(sorted, sorted.dropFirst()) {
            #expect(lhs.endTime <= rhs.startTime + 0.001, "overlapping spans selected: \(rendered)")
        }
        // Truth is induction → deepening with no fractionation cues.
        let phases = Set(segments.map(\.phase))
        #expect(phases.contains(.deepening), "deepening lost in final output: \(rendered)")
        #expect(!phases.contains(.fractionation), "spurious fractionation in final output: \(rendered)")
    }
}
