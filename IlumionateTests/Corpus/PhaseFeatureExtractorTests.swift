import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct PhaseFeatureExtractorTests {

    private func transcription() -> AudioTranscriptionResult {
        // Segment layout chosen so keyword hits land at deterministic buckets:
        //   "close your eyes" (3-word phrase, weight 3.0) → first word at t=0 → bucket 0
        //   "relax" (single induction word, weight 1.8) → t=5 → bucket 5
        //   "going deeper" (deepening) → first word at t=30 → bucket 30
        // With per-word timing = segment.duration / wordCount, using a 1-word
        // segment at t=5 guarantees an induction hit at exactly bucket 5.
        AudioTranscriptionResult(
            fullText: "close your eyes relax going deeper and deeper",
            segments: [
                AudioTranscriptionSegment(text: "close your eyes", timestamp: 0, duration: 5, confidence: 1),
                AudioTranscriptionSegment(text: "relax", timestamp: 5, duration: 1, confidence: 1),
                AudioTranscriptionSegment(text: "going deeper and deeper", timestamp: 30, duration: 30, confidence: 1),
            ],
            duration: 60, detectedLanguage: "en"
        )
    }

    @Test("Header and vector width are equal and constant across seconds")
    func headerMatchesWidth() {
        let extractor = PhaseFeatureExtractor(transcription: transcription())
        let names = PhaseFeatureExtractor.columnNames
        #expect(names.first == "position")
        #expect(names.contains("kw_induction"))
        #expect(extractor.featureVector(at: 0).values.count == names.count)
        #expect(extractor.featureVector(at: 45).values.count == names.count)
    }

    @Test("Position is second/duration and increases over time")
    func positionMonotonic() {
        let extractor = PhaseFeatureExtractor(transcription: transcription())
        let p0 = extractor.featureVector(at: 0).value(for: "position")
        let p30 = extractor.featureVector(at: 30).value(for: "position")
        #expect(p0 == 0.0)
        #expect(abs(p30 - 0.5) < 1e-9)
    }

    @Test("Keyword features reflect the hit-map (induction keywords fire early)")
    func keywordFeaturesPresent() {
        let extractor = PhaseFeatureExtractor(transcription: transcription())
        let early = extractor.featureVector(at: 5)
        #expect(early.value(for: "kw_induction") > 0)
    }
}
