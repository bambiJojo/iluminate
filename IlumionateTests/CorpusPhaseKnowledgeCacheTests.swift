import Foundation
import Testing
@testable import Ilumionate

struct CorpusPhaseKnowledgeCacheTests {

    @Test func shippingBundleContainsDistilledReviewedKnowledge() throws {
        let knowledge = try #require(CorpusPhaseKnowledgeSnapshot.loadDefault())

        #expect(knowledge.keywordWeights.count >= 7)
        #expect(knowledge.phraseAssociations.isEmpty == false)
        #expect(knowledge.transitionPriors.isEmpty == false)
        #expect(knowledge.fewShotExamples.isEmpty)
        #expect(
            knowledge.phraseAssociations.values
                .flatMap { $0 }
                .allSatisfy { association in
                    guard let sourceURL = association.sourceURL else { return true }
                    return sourceURL.hasPrefix("file:") == false
                        && sourceURL.hasPrefix("/") == false
                },
            "The shipping snapshot must not reveal private corpus file locations."
        )
    }

    @Test func bundledSnapshotRoundTripsDistilledAnalyzerKnowledge() throws {
        let association = HypnosisPhraseAssociation(
            phrase: "open your eyes",
            phase: .deepening,
            weight: 3.9,
            origin: .blended,
            sourceLabel: "reviewed corpus",
            sourceURL: nil,
            sourcePackIDs: ["general"],
            corpusSupport: 2.4,
            sectionCount: 3,
            exampleCount: 2
        )
        let knowledge = CorpusPhaseKnowledge(
            keywordWeights: [.induction: ["comfortable": 2.1]],
            phaseTokens: [.induction: ["comfortable"]],
            phraseWeights: [.deepening: ["open your eyes": 3.9]],
            phraseAssociations: [.deepening: [association]],
            sourcePackLabels: ["general": "General corpus"],
            keywordSourcePacks: [.induction: ["comfortable": ["general"]]],
            phraseSourcePacks: [.deepening: ["open your eyes": ["general"]]],
            transitionPriors: [.induction: [.deepening: 1.0]],
            fewShotExamples: [
                .init(
                    text: "Let yourself become comfortable as the session begins.",
                    position: 0.1,
                    correctPhase: HypnosisMetadata.Phase.induction.rawValue
                )
            ]
        )

        let data = try JSONEncoder().encode(
            CorpusPhaseKnowledgeSnapshot(
                knowledge: knowledge,
                fewShotExamples: knowledge.fewShotExamples
            )
        )
        let decoded = try JSONDecoder().decode(CorpusPhaseKnowledgeSnapshot.self, from: data)
            .knowledge

        #expect(decoded.keywordWeights[.induction]?["comfortable"] == 2.1)
        #expect(decoded.phaseTokens[.induction] == ["comfortable"])
        #expect(decoded.phraseAssociations[.deepening]?.first?.phrase == "open your eyes")
        #expect(decoded.keywordSourcePacks[.induction]?["comfortable"] == ["general"])
        #expect(decoded.transitionPriors[.induction]?[.deepening] == 1.0)
        #expect(decoded.fewShotExamples.first?.correctPhase == HypnosisMetadata.Phase.induction.rawValue)
    }

    @Test func repeatedReadsUseOneLoadedSnapshot() {
        let counter = LockedCounter()
        let cache = CorpusPhaseKnowledgeCache {
            counter.increment()
            return CorpusPhaseKnowledge(keywordWeights: [.induction: ["breathe": 2.0]])
        }

        _ = cache.knowledge()
        _ = cache.knowledge()

        #expect(counter.value == 1)
    }

    @Test func invalidationLoadsOneNewSnapshot() {
        let counter = LockedCounter()
        let cache = CorpusPhaseKnowledgeCache {
            counter.increment()
            return .empty
        }

        _ = cache.knowledge()
        cache.invalidate()
        _ = cache.knowledge()

        #expect(counter.value == 2)
    }

    @Test func recursiveLoaderUsesEmptyBootstrapKnowledge() {
        let holder = KnowledgeCacheHolder()
        let cache = CorpusPhaseKnowledgeCache {
            let bootstrap = holder.cache.knowledge()
            holder.sawEmptyBootstrap = bootstrap.keywordWeights.isEmpty
            return CorpusPhaseKnowledge(keywordWeights: [.induction: ["breathe": 2.0]])
        }
        holder.cache = cache

        let knowledge = cache.knowledge()

        #expect(holder.sawEmptyBootstrap)
        #expect(knowledge.keywordWeights[.induction]?["breathe"] == 2.0)
    }
}

struct CorpusPhaseKnowledgeTrustTests {
    private struct CachedTranscriptionPayload: Encodable {
        let schemaVersion: Int
        let cachedAt: Date
        let exampleID: UUID
        let audioSHA256: String
        let transcription: AudioTranscriptionResult
    }

    @Test func transcriptDerivedSilverLabelsDoNotTeachShippingKnowledge() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CorpusPhaseKnowledgeTrustTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cacheDirectory = root.appending(path: "cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let silver = LabeledFile(
            originalFilename: "derived.wav",
            storedAudioFilename: "derived.wav",
            audioDuration: 60,
            audioSHA256: "silver-audio-hash",
            expectedContentType: .hypnosis,
            expectedFrequencyBand: .init(lower: 0.5, upper: 8),
            phases: [
                .init(phase: .induction, startTime: 0, endTime: 30),
                .init(phase: .brainwashing, startTime: 30, endTime: 60)
            ],
            techniques: [],
            labeledAt: Date(timeIntervalSince1970: 1_000),
            labelerNotes: "  SILVER LABEL: transcript-only Bambi derivation; independent review required."
        )
        let trainingExample = silver.analyzerTrainingExample(
            exportedAt: Date(timeIntervalSince1970: 1_100),
            datasetRelativeAudioPath: "audio/derived.wav",
            datasetRelativeExamplePath: "examples/derived.json"
        )
        let example = AnalyzerOptimizationDataset.Example(
            example: trainingExample,
            audioURL: root.appending(path: "derived.wav")
        )
        let transcriptText = "silveronlytoken repeats silveronlytoken again and again. "
            + "Obey silveronlytoken as the programming repeats automatically."
        let transcription = AudioTranscriptionResult(
            fullText: transcriptText,
            segments: [
                .init(text: transcriptText, timestamp: 0, duration: 60, confidence: 1)
            ],
            duration: 60,
            detectedLanguage: "en"
        )
        let payload = CachedTranscriptionPayload(
            schemaVersion: 1,
            cachedAt: Date(timeIntervalSince1970: 1_200),
            exampleID: silver.id,
            audioSHA256: silver.audioSHA256,
            transcription: transcription
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(payload).write(
            to: cacheDirectory.appending(path: "\(silver.audioSHA256).json"),
            options: .atomic
        )

        let dataset = AnalyzerOptimizationDataset(
            corpusDirectory: root,
            datasetDirectory: root,
            datasetIndexURL: root.appending(path: "dataset.jsonl"),
            audioDirectory: root,
            transcriptCacheDirectory: cacheDirectory,
            examples: [example],
            issues: [],
            datasetHash: "test"
        )

        let knowledge = CorpusPhaseKnowledgeBuilder(dataset: dataset).build()

        #expect(knowledge.phaseTokens[.brainwashing]?.contains("silveronlytoken") != true)
        #expect(knowledge.transitionPriors[.induction]?[.brainwashing] == nil)
        #expect(knowledge.fewShotExamples.isEmpty)
    }
}

private nonisolated final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}

private nonisolated final class KnowledgeCacheHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var cacheStorage: CorpusPhaseKnowledgeCache?
    private var sawEmptyBootstrapStorage = false

    var cache: CorpusPhaseKnowledgeCache {
        get { lock.withLock { cacheStorage! } }
        set { lock.withLock { cacheStorage = newValue } }
    }

    var sawEmptyBootstrap: Bool {
        get { lock.withLock { sawEmptyBootstrapStorage } }
        set { lock.withLock { sawEmptyBootstrapStorage = newValue } }
    }
}
