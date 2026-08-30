//
//  BambiDerivedLabelingController.swift
//  LumeLabel
//
//  Unattended, no-playback transcription and silver-label derivation for audio
//  that must stay out of the human listening workflow.
//

import Foundation
import Observation

nonisolated struct BambiDerivedLabelingAvailability: Equatable, Sendable {
    let totalCount: Int
    let transcribedCount: Int
    let derivedCount: Int
    let pendingCount: Int
    let protectedHumanCount: Int

    init(files: [LabeledFile], transcribedHashes: Set<String>) {
        let scoped = files.filter(BambiSafetyPolicy.requiresTranscriptOnlyLabeling)
        totalCount = scoped.count
        transcribedCount = scoped.count {
            $0.audioSHA256.isEmpty == false && transcribedHashes.contains($0.audioSHA256)
        }
        derivedCount = scoped.count(where: BambiSafetyPolicy.isTranscriptOnlySilver)
        pendingCount = scoped.count { $0.phases.isEmpty }
        protectedHumanCount = scoped.count {
            $0.phases.isEmpty == false && BambiSafetyPolicy.isTranscriptOnlySilver($0) == false
        }
    }

    var actionTitle: String {
        switch pendingCount {
        case 0: "Safety Queue Complete"
        case 1: "Derive 1 Silver Label"
        default: "Derive \(pendingCount) Silver Labels"
        }
    }

    var summary: String {
        "\(derivedCount)/\(totalCount) silver · \(transcribedCount) transcribed · \(pendingCount) pending"
    }
}

nonisolated enum BambiDerivedLabelingQueue {
    static func pendingFiles(
        in files: [LabeledFile],
        transcribedHashes: Set<String>
    ) -> [LabeledFile] {
        files
            .filter {
                BambiSafetyPolicy.requiresTranscriptOnlyLabeling($0)
                    && $0.phases.isEmpty
            }
            .sorted { lhs, rhs in
                let lhsCached = transcribedHashes.contains(lhs.audioSHA256)
                let rhsCached = transcribedHashes.contains(rhs.audioSHA256)
                if lhsCached != rhsCached {
                    return lhsCached
                }
                return lhs.audioFilename.localizedStandardCompare(rhs.audioFilename) == .orderedAscending
            }
    }
}

@MainActor
@Observable
final class BambiDerivedLabelingController {
    static let shared = BambiDerivedLabelingController()

    enum Stage: String, Sendable {
        case transcribing = "Transcribing"
        case classifying = "Comparing transcript and intents"
        case saving = "Saving silver labels"
    }

    private(set) var isRunning = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var derived = 0
    private(set) var currentFilename: String?
    private(set) var stage: Stage?
    private(set) var statusMessage: String?
    private(set) var failures: [(filename: String, reason: String)] = []

    private var task: Task<Void, Never>?

    var progress: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    func start(corpus: TrainingCorpusManager) {
        guard isRunning == false else { return }
        let transcribedHashes = TranscriptInventory.availableHashes(
            in: corpus.analyzerDatasetDirectory
        )
        let pending = BambiDerivedLabelingQueue.pendingFiles(
            in: corpus.labeledFiles,
            transcribedHashes: transcribedHashes
        )
        guard pending.isEmpty == false else {
            statusMessage = "No unlabeled Bambi files remain in the safety queue."
            return
        }

        isRunning = true
        completed = 0
        derived = 0
        total = pending.count
        failures = []
        statusMessage = "Starting transcript-only safety run…"

        task = Task { [weak self] in
            do {
                let catalogExamples = try await Task.detached(priority: .utility) {
                    try KnownAudioIntentExampleStore.load()
                }.value
                let analyzer = AudioAnalyzer()

                for file in pending {
                    try Task.checkCancellation()
                    self?.currentFilename = file.audioFilename
                    do {
                        let transcript = try await Self.transcription(
                            for: file,
                            corpus: corpus,
                            analyzer: analyzer,
                            setStage: { self?.stage = $0 }
                        )
                        self?.stage = .classifying
                        let proposal = try await Self.proposal(
                            for: file,
                            transcript: transcript,
                            audioURL: corpus.audioURL(for: file),
                            catalogExamples: catalogExamples
                        )
                        guard let proposal else {
                            throw DerivationError.noPhaseEvidence
                        }
                        self?.stage = .saving
                        let labeled = try proposal.applying(to: file)
                        _ = try await corpus.save(labeled)
                        self?.derived += 1
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        self?.failures.append((file.audioFilename, error.localizedDescription))
                    }
                    self?.completed += 1
                }
                self?.finish()
            } catch is CancellationError {
                self?.finish(cancelled: true)
            } catch {
                self?.failures.append(("Catalog", error.localizedDescription))
                self?.finish()
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    private static func transcription(
        for file: LabeledFile,
        corpus: TrainingCorpusManager,
        analyzer: AudioAnalyzer,
        setStage: @MainActor (Stage) -> Void
    ) async throws -> AudioTranscriptionResult {
        let datasetDirectory = corpus.analyzerDatasetDirectory
        let cacheTask = Task.detached(priority: .utility) {
            try TranscriptCacheStore.load(for: file, in: datasetDirectory)
        }
        if let cached = try await cacheTask.value {
            return cached
        }

        setStage(.transcribing)
        let audioURL = corpus.audioURL(for: file)
        let values = try? audioURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
        let audioFile = AudioFile(
            id: file.id,
            filename: audioURL.standardizedFileURL.path(),
            duration: file.audioDuration,
            fileSize: Int64(values?.fileSize ?? 0),
            createdDate: values?.creationDate ?? file.labeledAt
        )
        let result = try await analyzer.transcribe(audioFile: audioFile)
        try await Task.detached(priority: .utility) {
            try TranscriptCacheStore.save(result, for: file, in: datasetDirectory)
        }.value
        return result
    }

    private static func proposal(
        for file: LabeledFile,
        transcript: AudioTranscriptionResult,
        audioURL: URL,
        catalogExamples: [SemanticPhaseAnalyzer.Example]
    ) async throws -> TranscriptOnlySilverLabeler.Proposal? {
        let keywordTask = Task.detached(priority: .utility) {
            HypnosisPhaseAnalyzer().analyzeTranscription(transcript)
        }
        let semanticTask = Task.detached(priority: .utility) {
            try SemanticPhaseAnalyzer(examples: catalogExamples).analyze(transcription: transcript)
        }
        let toneTask = Task.detached(priority: .utility) {
            try BackgroundToneAnalyzer.analyze(audioURL: audioURL).candidates
        }

        return try await withTaskCancellationHandler {
            let keywordSegments = await keywordTask.value
            try Task.checkCancellation()
            let semanticSignals: [TranscriptOnlySilverLabeler.SemanticSignal]
            do {
                semanticSignals = try await semanticTask.value.segments.map {
                    .init(
                        phase: $0.phase,
                        startTime: $0.startTime,
                        endTime: $0.endTime,
                        confidence: $0.confidence
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                semanticSignals = []
            }
            let toneCandidates: [BackgroundToneCandidate]
            do {
                toneCandidates = try await toneTask.value
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                toneCandidates = []
            }
            try Task.checkCancellation()

            return TranscriptOnlySilverLabeler.makeProposal(
                duration: file.audioDuration,
                keywordSegments: keywordSegments,
                semanticSignals: semanticSignals,
                toneCandidates: toneCandidates,
                transcriptConfidence: transcript.averageConfidence,
                catalogExampleCount: catalogExamples.count
            )
        } onCancel: {
            keywordTask.cancel()
            semanticTask.cancel()
            toneTask.cancel()
        }
    }

    private func finish(cancelled: Bool = false) {
        isRunning = false
        currentFilename = nil
        stage = nil
        task = nil
        if cancelled {
            statusMessage = "Stopped after \(completed) of \(total). Saved transcripts and silver labels will resume next time."
        } else if failures.isEmpty {
            statusMessage = "Derived \(derived) transcript-only silver label\(derived == 1 ? "" : "s")."
        } else {
            statusMessage = "Derived \(derived) of \(total); \(failures.count) need attention."
        }
    }
}

private nonisolated enum DerivationError: LocalizedError {
    case noPhaseEvidence

    var errorDescription: String? {
        "The transcript did not contain enough phase evidence to create a silver timeline."
    }
}
