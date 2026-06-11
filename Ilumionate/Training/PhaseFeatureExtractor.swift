//  PhaseFeatureExtractor.swift
//  Ilumionate
//
//  Per-second feature vectors for the learned phase model. Reuses the SAME
//  extractors the analyzer uses (keyword hit-map, transcript features, technique
//  markers, position) so training and inference features match. Deterministic.
//
import Foundation

/// An ordered, named numeric feature vector for one second of a session.
struct PhaseFeatureVector: Sendable {
    let values: [Double]

    /// Value for a named column (linear lookup; vectors are small).
    func value(for column: String) -> Double {
        guard let index = PhaseFeatureExtractor.columnNames.firstIndex(of: column) else { return 0 }
        return values[index]
    }
}

@MainActor
struct PhaseFeatureExtractor {
    private let duration: TimeInterval
    private let bucketCount: Int
    private let hitMap: [[HypnosisMetadata.Phase: Double]]
    private let analysis: TranscriptAnalysis
    private let markerDensity: [Double]   // markers landing in each 1s bucket

    /// Stable feature column order (excludes trace columns and the label).
    static let columnNames: [String] =
        ["position"]
        + TrancePhase.orderedHypnosisPhases.map { "kw_\($0.rawValue)" }
        + ["tf_wpm", "tf_coverage", "tf_lexical", "tf_repetition"]
        + ["tech_marker_density"]

    init(transcription: AudioTranscriptionResult) {
        self.duration = max(transcription.duration, 1)
        self.bucketCount = max(1, Int(ceil(transcription.duration)))
        let analyzer = HypnosisPhaseAnalyzer()
        let words = analyzer.approximateWordTimestamps(from: transcription.segments)
        self.hitMap = words.isEmpty
            ? Array(repeating: [:], count: bucketCount)
            : analyzer.buildHitMap(wordTimestamps: words, bucketCount: bucketCount)
        self.analysis = TranscriptFeatureAnalyzer().analyze(transcription: transcription, phases: nil)
        let detector = TechniqueDetector()
        let markers: [LinguisticMarker] = words.isEmpty
            ? []
            : detector.detect(
                wordTimestamps: words,
                segments: transcription.segments,
                prosodic: nil,
                duration: transcription.duration
              ).markers
        var density = Array(repeating: 0.0, count: bucketCount)
        for marker in markers {
            let bucket = min(max(Int(marker.timestamp), 0), bucketCount - 1)
            density[bucket] += 1
        }
        self.markerDensity = density
    }

    func featureVector(at second: Int) -> PhaseFeatureVector {
        let bucket = min(max(second, 0), bucketCount - 1)
        var values: [Double] = [Double(second) / duration]
        for phase in TrancePhase.orderedHypnosisPhases {
            values.append(hitMap[bucket][phase] ?? 0)
        }
        let section = analysis.section(at: Double(second) + 0.5)
        values.append(section?.normalizedWordsPerMinute ?? 0)
        values.append(section?.normalizedSpeechCoverage ?? 0)
        values.append(section?.normalizedLexicalDiversity ?? 0)
        values.append(section?.normalizedRepetitionDensity ?? 0)
        values.append(markerDensity[bucket])
        return PhaseFeatureVector(values: values)
    }
}
