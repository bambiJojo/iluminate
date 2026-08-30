//
//  LumeLabelTests.swift
//  LumeLabelTests
//

import Foundation
import Testing
@testable import LumeLabel

struct LumeLabelTests {
    @Test
    func bundledAnalyzerConfigSupportsTheSevenLightControlPhases() throws {
        let url = try #require(
            Bundle.main.url(forResource: "AnalyzerConfig_default", withExtension: "json")
        )
        let config = try JSONDecoder().decode(
            AnalyzerConfig.self,
            from: Data(contentsOf: url)
        )
        let instructions = config.chunkedAnalyzer.systemInstructions

        #expect(instructions.contains("fractionation: deliberate repeated waking"))
        #expect(instructions.contains("post_hypnotic_conditioning: triggers"))
        #expect(instructions.contains("fractionation is a technique") == false)
        #expect(instructions.contains("Phases ALWAYS occur in this strict order") == false)
    }

    @Test
    @MainActor
    func corpusManagerReportsWhenItsInitialLoadFinishes() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)

        #expect(manager.hasFinishedInitialLoad == false)
        await manager.reload()
        #expect(manager.hasFinishedInitialLoad)
    }

    @Test
    func bambiSafetyQueueUsesCachedTranscriptsFirstAndProtectsExistingLabels() {
        var cached = makeFile(phases: [])
        cached.originalFilename = "Bambi cached.mp3"
        cached.audioSHA256 = "cached-hash"

        var uncached = makeFile(phases: [])
        uncached.originalFilename = "Bambi uncached.mp3"
        uncached.audioSHA256 = "uncached-hash"

        var protected = makeFile(phases: [
            .init(phase: .suggestions, startTime: 0, endTime: 60)
        ])
        protected.originalFilename = "Bambi human labeled.mp3"
        protected.audioSHA256 = "protected-hash"

        let pending = BambiDerivedLabelingQueue.pendingFiles(
            in: [uncached, protected, cached],
            transcribedHashes: [cached.audioSHA256]
        )

        #expect(pending.map(\.id) == [cached.id, uncached.id])
    }

    @Test
    @MainActor
    func goldSprintNeverQueuesBambiFilesForListening() throws {
        let defaults = try makeIsolatedUserDefaults()
        var safeFile = makeFile(phases: [])
        safeFile.originalFilename = "ordinary-session.mp3"
        var bambiFile = makeFile(phases: [])
        bambiFile.originalFilename = "Sapphic Bambi Remix.mp3"
        let sprint = LabelingSprintController(defaults: defaults)

        _ = sprint.start(
            files: [bambiFile, safeFile],
            targetCount: 2,
            transcribedHashes: []
        )

        #expect(sprint.queuedFiles(from: [bambiFile, safeFile]).map(\.id) == [safeFile.id])
    }

    @Test
    @MainActor
    func goldSprintNeverQueuesFilesWhoseCachedTranscriptContainsBambi() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeIsolatedUserDefaults()
        var safeFile = makeFile(phases: [])
        safeFile.originalFilename = "ordinary-safe-session.mp3"
        safeFile.audioSHA256 = "safe-transcript-hash"
        var bambiFile = makeFile(phases: [])
        bambiFile.originalFilename = "ordinary-looking-session.mp3"
        bambiFile.audioSHA256 = "bambi-transcript-hash"
        let transcript = AudioTranscriptionResult(
            fullText: Array(repeating: "Bambi", count: 136).joined(separator: " "),
            segments: [],
            duration: bambiFile.audioDuration,
            detectedLanguage: "en"
        )
        try TranscriptCacheStore.save(transcript, for: bambiFile, in: directory)
        let bambiTranscriptHashes = BambiSafetyPolicy.transcriptHashesRequiringTranscriptOnlyLabeling(
            in: [bambiFile, safeFile],
            datasetDirectory: directory
        )
        let sprint = LabelingSprintController(defaults: defaults)

        _ = sprint.start(
            files: [bambiFile, safeFile],
            targetCount: 2,
            transcribedHashes: [bambiFile.audioSHA256],
            bambiTranscriptHashes: bambiTranscriptHashes
        )

        #expect(bambiTranscriptHashes == [bambiFile.audioSHA256])
        #expect(sprint.queuedFiles(
            from: [bambiFile, safeFile],
            bambiTranscriptHashes: bambiTranscriptHashes
        ).map(\.id) == [safeFile.id])
    }

    @Test
    @MainActor
    func resumingGoldSprintRemovesNewlyDetectedBambiTranscripts() throws {
        let defaults = try makeIsolatedUserDefaults()
        var safeFile = makeFile(phases: [])
        safeFile.originalFilename = "ordinary-safe-session.mp3"
        safeFile.audioSHA256 = "safe-transcript-hash"
        var bambiFile = makeFile(phases: [])
        bambiFile.originalFilename = "ordinary-looking-session.mp3"
        bambiFile.audioSHA256 = "bambi-transcript-hash"
        let files = [bambiFile, safeFile]
        let sprint = LabelingSprintController(defaults: defaults)
        _ = sprint.start(files: files, targetCount: 2, transcribedHashes: [])

        let relaunched = LabelingSprintController(defaults: defaults)
        let resumedID = relaunched.resume(
            files: files,
            bambiTranscriptHashes: [bambiFile.audioSHA256]
        )

        #expect(resumedID == safeFile.id)
        #expect(relaunched.queuedFiles(
            from: files,
            bambiTranscriptHashes: [bambiFile.audioSHA256]
        ).map(\.id) == [safeFile.id])
    }

    @Test
    func transcriptOnlyDerivationProducesContiguousSilverLabelsWithProvenance() throws {
        var file = makeFile(phases: [])
        file.originalFilename = "Bambi custom mix.mp3"
        file.audioDuration = 600
        let keywordSegments: [PhaseSegment] = [
            .init(phase: .induction, startTime: 0, endTime: 120, characteristics: "", tranceDepthEstimate: 0.3),
            .init(phase: .deepening, startTime: 120, endTime: 300, characteristics: "", tranceDepthEstimate: 0.6),
            .init(phase: .suggestions, startTime: 300, endTime: 600, characteristics: "", tranceDepthEstimate: 0.7),
        ]
        let semanticSignals = [
            TranscriptOnlySilverLabeler.SemanticSignal(
                phase: .induction, startTime: 0, endTime: 130, confidence: 0.82
            ),
            TranscriptOnlySilverLabeler.SemanticSignal(
                phase: .deepening, startTime: 130, endTime: 300, confidence: 0.76
            ),
            TranscriptOnlySilverLabeler.SemanticSignal(
                phase: .suggestions, startTime: 300, endTime: 600, confidence: 0.79
            ),
        ]

        let proposal = try #require(TranscriptOnlySilverLabeler.makeProposal(
            duration: file.audioDuration,
            keywordSegments: keywordSegments,
            semanticSignals: semanticSignals,
            toneCandidates: [.init(time: 130, strength: 0.8)],
            transcriptConfidence: 0.9,
            catalogExampleCount: 40
        ))
        let derived = try proposal.applying(to: file)

        #expect(derived.labelerNotes.hasPrefix(BambiSafetyPolicy.silverLabelPrefix))
        #expect(derived.phases.map(\.phase) == [.induction, .deepening, .suggestions])
        #expect(derived.phases.first?.startTime == 0)
        #expect(derived.phases[0].endTime == 130)
        #expect(derived.phases[1].startTime == 130)
        #expect(derived.phases.last?.endTime == 600)
        #expect(derived.phases.allSatisfy { $0.notes?.contains("catalog intent") == true })
        _ = try derived.validatedForPersistence()
    }

    @Test
    func bundledBambiTranscriptsAndIntentsBecomeSemanticPhaseExamples() throws {
        let examples = try KnownAudioIntentExampleStore.load()
        let phases = Set(examples.map(\.phase))

        #expect(examples.count >= 40)
        #expect(phases.contains(.induction))
        #expect(phases.contains(.deepening))
        #expect(phases.contains(.brainwashing))
        #expect(phases.contains(.conditioning))
        #expect(phases.contains(.emergence))
    }

    @Test
    func transcriptCacheStoreRoundTripsAnUnattendedTranscript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var file = makeFile(phases: [])
        file.audioSHA256 = "safe-cache-key"
        let result = AudioTranscriptionResult(
            fullText: "relax and then awaken",
            segments: [
                .init(text: "relax and then awaken", timestamp: 0, duration: 30, confidence: 0.8)
            ],
            duration: 30,
            detectedLanguage: "en"
        )

        try TranscriptCacheStore.save(result, for: file, in: directory)
        let cached = try TranscriptCacheStore.load(for: file, in: directory)
        let loaded = try #require(cached)

        #expect(loaded.fullText == result.fullText)
        #expect(loaded.duration == result.duration)
        #expect(loaded.segments.count == 1)
    }

    @Test
    func bambiDerivationAvailabilityProtectsHumanLabelsAndResumesRemainingWork() {
        var pending = makeFile(phases: [])
        pending.originalFilename = "Bambi pending.mp3"
        pending.audioSHA256 = "pending"
        var completed = makeFile(phases: [
            .init(phase: .suggestions, startTime: 0, endTime: 60)
        ])
        completed.originalFilename = "Bambi completed.mp3"
        completed.audioSHA256 = "completed"
        completed.labelerNotes = "\(BambiSafetyPolicy.silverLabelPrefix); not human reviewed."
        var protected = makeFile(phases: [
            .init(phase: .deepening, startTime: 0, endTime: 60)
        ])
        protected.originalFilename = "Bambi human labeled.mp3"
        protected.audioSHA256 = "protected"
        protected.labelerNotes = "Reviewed by another labeler"
        var unrelated = makeFile(phases: [])
        unrelated.originalFilename = "ordinary.mp3"

        let availability = BambiDerivedLabelingAvailability(
            files: [pending, completed, protected, unrelated],
            transcribedHashes: ["pending", "completed"]
        )

        #expect(availability.totalCount == 3)
        #expect(availability.derivedCount == 1)
        #expect(availability.pendingCount == 1)
        #expect(availability.protectedHumanCount == 1)
        #expect(availability.transcribedCount == 2)
    }

    @Test
    @MainActor
    func startingGoldSprintQueuesOnlyEnoughWorkToReachTheGoal() throws {
        let defaults = try makeIsolatedUserDefaults()
        let goldFiles = (0..<3).map { index in
            var file = makeFile(phases: [
                .init(phase: .induction, startTime: 0, endTime: 60)
            ])
            file.originalFilename = "gold-\(index).mp3"
            return file
        }
        let unlabeledFiles = (0..<30).map { index in
            var file = makeFile(phases: [])
            file.originalFilename = "pending-\(index).mp3"
            file.audioDuration = TimeInterval(600 + index * 60)
            return file
        }
        let files = goldFiles + unlabeledFiles
        let sprint = LabelingSprintController(defaults: defaults)

        let firstFileID = sprint.start(
            files: files,
            targetCount: 25,
            transcribedHashes: []
        )

        let progress = sprint.progress(in: files)
        let queuedFiles = sprint.queuedFiles(from: files)
        #expect(sprint.isActive)
        #expect(progress.completedCount == 3)
        #expect(progress.targetCount == 25)
        #expect(progress.remainingCount == 22)
        #expect(queuedFiles.count == 22)
        #expect(firstFileID == queuedFiles.first?.id)
        #expect(queuedFiles.allSatisfy { $0.phases.isEmpty })
    }

    @Test
    @MainActor
    func deferringASprintFileReplacesItAndMovesToTheNextFile() throws {
        let defaults = try makeIsolatedUserDefaults()
        let gold = makeFile(phases: [
            .init(phase: .induction, startTime: 0, endTime: 60)
        ])
        let unlabeled = (0..<4).map { index in
            var file = makeFile(phases: [])
            file.originalFilename = "pending-\(index).mp3"
            file.audioDuration = TimeInterval(600 + index * 60)
            return file
        }
        let files = [gold] + unlabeled
        let sprint = LabelingSprintController(defaults: defaults)
        let deferredID = try #require(sprint.start(
            files: files,
            targetCount: 3,
            transcribedHashes: []
        ))

        let nextID = sprint.deferFile(
            fileID: deferredID,
            files: files,
            transcribedHashes: []
        )

        let queuedFiles = sprint.queuedFiles(from: files)
        #expect(queuedFiles.count == 2)
        #expect(queuedFiles.contains { $0.id == deferredID } == false)
        #expect(nextID == queuedFiles.first?.id)
        #expect(sprint.progress(in: files).deferredCount == 1)
    }

    @Test
    @MainActor
    func completingASprintFileAdvancesWithoutRefillingFinishedWork() throws {
        let defaults = try makeIsolatedUserDefaults()
        let gold = makeFile(phases: [
            .init(phase: .induction, startTime: 0, endTime: 60)
        ])
        let unlabeled = (0..<3).map { index in
            var file = makeFile(phases: [])
            file.originalFilename = "pending-\(index).mp3"
            file.audioDuration = TimeInterval(600 + index * 60)
            return file
        }
        let startingFiles = [gold] + unlabeled
        let sprint = LabelingSprintController(defaults: defaults)
        let completedID = try #require(sprint.start(
            files: startingFiles,
            targetCount: 3,
            transcribedHashes: []
        ))
        var completedFile = try #require(startingFiles.first { $0.id == completedID })
        completedFile.phases = [
            .init(phase: .induction, startTime: 0, endTime: completedFile.audioDuration)
        ]
        let updatedFiles = startingFiles.map { $0.id == completedID ? completedFile : $0 }

        let nextID = sprint.advanceAfterSaving(
            fileID: completedID,
            files: updatedFiles
        )

        let queuedFiles = sprint.queuedFiles(from: updatedFiles)
        #expect(sprint.progress(in: updatedFiles).completedCount == 2)
        #expect(sprint.progress(in: updatedFiles).remainingCount == 1)
        #expect(queuedFiles.count == 1)
        #expect(nextID == queuedFiles.first?.id)
    }

    @Test
    @MainActor
    func goldSprintQueueAndDeferralsSurviveRelaunch() throws {
        let defaults = try makeIsolatedUserDefaults()
        let files = (0..<5).map { index in
            var file = makeFile(phases: [])
            file.originalFilename = "pending-\(index).mp3"
            file.audioDuration = TimeInterval(600 + index * 60)
            return file
        }
        let sprint = LabelingSprintController(defaults: defaults)
        let deferredID = try #require(sprint.start(
            files: files,
            targetCount: 3,
            transcribedHashes: []
        ))
        _ = sprint.deferFile(
            fileID: deferredID,
            files: files,
            transcribedHashes: []
        )
        let expectedQueue = sprint.queuedFiles(from: files).map(\.id)

        let relaunched = LabelingSprintController(defaults: defaults)

        #expect(relaunched.isActive)
        #expect(relaunched.targetCount == 3)
        #expect(relaunched.progress(in: files).deferredCount == 1)
        #expect(relaunched.queuedFiles(from: files).map(\.id) == expectedQueue)
    }

    @Test
    @MainActor
    func resumingBeforeTheCorpusLoadsDoesNotEraseThePersistedSprint() throws {
        let defaults = try makeIsolatedUserDefaults()
        let files = (0..<4).map { index in
            var file = makeFile(phases: [])
            file.originalFilename = "pending-\(index).mp3"
            file.audioDuration = TimeInterval(600 + index * 60)
            return file
        }
        let sprint = LabelingSprintController(defaults: defaults)
        _ = sprint.start(files: files, targetCount: 3, transcribedHashes: [])
        let expectedQueue = sprint.queuedFiles(from: files).map(\.id)

        let relaunched = LabelingSprintController(defaults: defaults)
        let earlySelection = relaunched.resume(files: [])

        #expect(earlySelection == nil)
        #expect(relaunched.isActive)
        #expect(relaunched.hasPlan)
        #expect(relaunched.resume(files: files) == expectedQueue.first)
        #expect(relaunched.queuedFiles(from: files).map(\.id) == expectedQueue)
    }

    @Test
    @MainActor
    func pausingAndResumingGoldSprintKeepsTheExistingPlan() throws {
        let defaults = try makeIsolatedUserDefaults()
        let files = (0..<4).map { index in
            var file = makeFile(phases: [])
            file.originalFilename = "pending-\(index).mp3"
            return file
        }
        let sprint = LabelingSprintController(defaults: defaults)
        _ = sprint.start(files: files, targetCount: 3, transcribedHashes: [])
        let originalQueue = sprint.queuedFiles(from: files).map(\.id)

        sprint.pause()
        let relaunched = LabelingSprintController(defaults: defaults)
        let resumedID = relaunched.resume(files: files)

        #expect(relaunched.hasPlan)
        #expect(relaunched.isActive)
        #expect(relaunched.queuedFiles(from: files).map(\.id) == originalQueue)
        #expect(resumedID == originalQueue.first)
    }

    @Test
    @MainActor
    func goldSprintSamplesAcrossFileDurationsInsteadOfChoosingOnlyShortFiles() throws {
        let defaults = try makeIsolatedUserDefaults()
        let files = (1...100).map { minutes in
            var file = makeFile(phases: [])
            file.originalFilename = "duration-\(minutes).mp3"
            file.audioDuration = TimeInterval(minutes * 60)
            return file
        }
        let sprint = LabelingSprintController(defaults: defaults)

        _ = sprint.start(files: files, targetCount: 10, transcribedHashes: [])

        let queuedDurations = sprint.queuedFiles(from: files).map(\.audioDuration)
        #expect(queuedDurations.count == 10)
        #expect(queuedDurations.min() == 60)
        #expect(queuedDurations.max() == 6_000)
    }

    @Test
    func bulkTranscriptionAvailabilityReportsOnlyMissingAudio() {
        var cached = makeFile(phases: [])
        cached.originalFilename = "cached.mp3"
        cached.audioSHA256 = "cached-hash"
        var missingA = makeFile(phases: [])
        missingA.originalFilename = "missing-a.mp3"
        missingA.audioSHA256 = "missing-a-hash"
        var missingB = makeFile(phases: [])
        missingB.originalFilename = "missing-b.mp3"
        missingB.audioSHA256 = "missing-b-hash"

        let availability = BulkTranscriptionAvailability(
            files: [cached, missingA, missingB],
            transcribedHashes: ["cached-hash"]
        )

        #expect(availability.cachedCount == 1)
        #expect(availability.pendingCount == 2)
        #expect(availability.totalCount == 3)
        #expect(availability.actionTitle == "Transcribe 2 Missing")
    }

    @Test
    func markingTransitionsBuildsContiguousUnnamedSegments() {
        var labeling = TransitionLabelingDraft(duration: 100, phases: [])

        labeling.markBoundary(at: 25)
        labeling.markBoundary(at: 70)

        #expect(labeling.segments.map(\.startTime) == [0, 25, 70])
        #expect(labeling.segments.map(\.endTime) == [25, 70, 100])
        #expect(labeling.segments.allSatisfy { $0.phase == nil })
        #expect(labeling.boundaryCount == 2)
    }

    @Test
    func namingASegmentAdvancesToTheNextUnnamedSegment() throws {
        var labeling = TransitionLabelingDraft(duration: 100, phases: [])
        labeling.markBoundary(at: 40)
        let first = try #require(labeling.segments.first)
        let second = try #require(labeling.segments.last)

        let nextSegmentID = labeling.assign(.induction, toSegmentID: first.id)

        #expect(labeling.segments.first?.phase == .induction)
        #expect(labeling.unassignedCount == 1)
        #expect(nextSegmentID == second.id)
    }

    @Test
    func draftOnlyMaterializesCompleteLabelsAndPreservesSamePhaseBoundaries() throws {
        var labeling = TransitionLabelingDraft(duration: 100, phases: [])
        labeling.markBoundary(at: 40)
        let first = try #require(labeling.segments.first)
        let second = try #require(labeling.segments.last)

        labeling.assign(.deepening, toSegmentID: first.id)
        #expect(labeling.labeledPhases == nil)
        #expect(!labeling.isReadyToSave)

        labeling.assign(.deepening, toSegmentID: second.id)
        let phases = try #require(labeling.labeledPhases)
        #expect(labeling.isReadyToSave)
        #expect(phases.count == 2)
        #expect(phases.map(\.phase) == [.deepening, .deepening])
        #expect(phases.map(\.startTime) == [0, 40])
    }

    @Test
    func movingABoundaryChangesOnlyItsAdjacentSegments() throws {
        var labeling = TransitionLabelingDraft(duration: 100, phases: [])
        labeling.markBoundary(at: 30)
        labeling.markBoundary(at: 70)
        let movingSegment = try #require(labeling.segments.dropFirst().first)

        labeling.moveBoundary(startingSegmentID: movingSegment.id, to: 45)

        #expect(labeling.segments.map(\.startTime) == [0, 45, 70])
        #expect(labeling.segments.map(\.endTime) == [45, 70, 100])
    }

    @Test
    func readinessExplainsCoverageGapsAtLabelTime() {
        let labeling = TransitionLabelingDraft(
            duration: 100,
            phases: [
                .init(phase: .induction, startTime: 0, endTime: 40),
                .init(phase: .deepening, startTime: 50, endTime: 100)
            ]
        )

        #expect(labeling.readinessIssue == .gap(afterSegment: 0))
        #expect(labeling.readinessIssue?.message == "There is a gap between segments 1 and 2.")
    }

    @Test
    func removingABoundaryMakesAConflictingMergedSegmentUnnamed() throws {
        var labeling = TransitionLabelingDraft(duration: 100, phases: [])
        labeling.markBoundary(at: 40)
        let first = try #require(labeling.segments.first)
        let second = try #require(labeling.segments.last)
        labeling.assign(.induction, toSegmentID: first.id)
        labeling.assign(.deepening, toSegmentID: second.id)

        labeling.removeBoundary(startingSegmentID: second.id)

        #expect(labeling.segments.count == 1)
        #expect(labeling.segments.first?.startTime == 0)
        #expect(labeling.segments.first?.endTime == 100)
        #expect(labeling.segments.first?.phase == nil)
    }

    @Test
    @MainActor
    func incompleteTransitionWorkflowCannotOverwritePersistedLabels() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "incomplete/source.wav"),
            frequency: 330
        )
        let imported = try await manager.importAudio(from: source)
        let editor = LabelingDetailEditor(file: imported, corpus: manager)
        editor.currentTime = 0.75
        editor.markBoundaryAtPlayhead()

        let didSave = await editor.save()

        #expect(!didSave)
        #expect(editor.alertMessage == "Name every segment before saving this file.")
        #expect(manager.file(withID: imported.id)?.phases.isEmpty == true)
    }

    @Test
    @MainActor
    func switchingFilesRecoversIncompleteLabelingWork() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "recovery/source.wav"),
            frequency: 330
        )
        let imported = try await manager.importAudio(from: source)
        let editor = LabelingDetailEditor(file: imported, corpus: manager)
        editor.currentTime = 0.75
        editor.markBoundaryAtPlayhead()
        editor.beginPhaseNaming()
        editor.assignSelectedPhase(.induction)

        editor.cleanup()

        let reopened = LabelingDetailEditor(
            file: try #require(manager.file(withID: imported.id)),
            corpus: manager
        )
        await reopened.restoreWorkInProgressIfAvailable()

        #expect(reopened.labelingSegments.count == 2)
        #expect(reopened.labelingSegments.map(\.startTime) == [0, 0.75])
        #expect(reopened.labelingSegments.map(\.phase) == [.induction, nil])
        #expect(reopened.unassignedSegmentCount == 1)
    }

    @Test
    @MainActor
    func relaunchRecoversIncompleteLabelingWorkFromDisk() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "relaunch/source.wav"),
            frequency: 330
        )
        let imported = try await manager.importAudio(from: source)
        let firstStore = LabelingDraftRecoveryStore()
        let editor = LabelingDetailEditor(
            file: imported,
            corpus: manager,
            recoveryStore: firstStore
        )
        editor.currentTime = 0.75
        editor.markBoundaryAtPlayhead()
        editor.beginPhaseNaming()
        editor.assignSelectedPhase(.induction)

        try await waitUntil { editor.saveState == .draftSaved }
        #expect(editor.saveState == .draftSaved)

        let relaunched = LabelingDetailEditor(
            file: try #require(manager.file(withID: imported.id)),
            corpus: manager,
            recoveryStore: LabelingDraftRecoveryStore()
        )
        await relaunched.restoreWorkInProgressIfAvailable()

        #expect(relaunched.labelingSegments.count == 2)
        #expect(relaunched.labelingSegments.map(\.phase) == [.induction, nil])
        #expect(relaunched.saveState == .draftSaved)
    }

    @Test
    @MainActor
    func completedTimelineAutosavesWithoutPressingSave() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "autosave/source.wav"),
            frequency: 330
        )
        let imported = try await manager.importAudio(from: source)
        let editor = LabelingDetailEditor(
            file: imported,
            corpus: manager,
            recoveryStore: LabelingDraftRecoveryStore()
        )
        editor.currentTime = 0.75
        editor.markBoundaryAtPlayhead()
        editor.beginPhaseNaming()
        editor.assignSelectedPhase(.induction)
        editor.assignSelectedPhase(.deepening)

        try await waitUntil {
            manager.file(withID: imported.id)?.phases.count == 2
                && editor.saveState == .saved
        }

        let saved = try #require(manager.file(withID: imported.id))
        #expect(saved.phases.map(\.phase) == [.induction, .deepening])
        #expect(saved.phases.map(\.startTime) == [0, 0.75])
        #expect(editor.saveState == .saved)
    }

    @Test
    @MainActor
    func completedAutosaveIsNotMistakenForANewerRecoveryDraftAfterRelaunch() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "saved-relaunch/source.wav"),
            frequency: 330
        )
        let imported = try await manager.importAudio(from: source)
        let editor = LabelingDetailEditor(
            file: imported,
            corpus: manager,
            recoveryStore: LabelingDraftRecoveryStore()
        )
        editor.currentTime = 0.75
        editor.markBoundaryAtPlayhead()
        editor.beginPhaseNaming()
        editor.assignSelectedPhase(.induction)
        editor.assignSelectedPhase(.deepening)
        try await waitUntil {
            manager.file(withID: imported.id)?.phases.count == 2
                && editor.saveState == .saved
        }

        let relaunchedManager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        await relaunchedManager.reload()
        let relaunched = LabelingDetailEditor(
            file: try #require(relaunchedManager.file(withID: imported.id)),
            corpus: relaunchedManager,
            recoveryStore: LabelingDraftRecoveryStore()
        )
        await relaunched.restoreWorkInProgressIfAvailable()

        #expect(relaunched.labelingSegments.map(\.phase) == [.induction, .deepening])
        #expect(relaunched.saveState == .saved)
    }

    @Test
    @MainActor
    func completedTransitionWorkflowPersistsSamePhaseBoundaries() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "complete/source.wav"),
            frequency: 330
        )
        let imported = try await manager.importAudio(from: source)
        let editor = LabelingDetailEditor(file: imported, corpus: manager)
        editor.currentTime = 0.75
        editor.markBoundaryAtPlayhead()
        editor.beginPhaseNaming()
        editor.assignSelectedPhase(.deepening)
        editor.assignSelectedPhase(.deepening)

        await editor.save()

        let saved = try #require(manager.file(withID: imported.id))
        #expect(saved.phases.count == 2)
        #expect(saved.phases.map(\.phase) == [.deepening, .deepening])
        #expect(saved.phases.map(\.startTime) == [0, 0.75])
    }

    @Test
    @MainActor
    func cleanupReleasesPreparedAudioSession() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "cleanup/source.wav"),
            frequency: 330
        )
        let imported = try await manager.importAudio(from: source)
        let editor = LabelingDetailEditor(file: imported, corpus: manager)

        editor.preparePlayer()
        #expect(editor.hasAudioPlaybackSession)

        editor.cleanup()
        #expect(!editor.hasAudioPlaybackSession)
    }

    @Test
    @MainActor
    func cleanupClearsAnalyzerDiagnosticsProgress() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "diagnostics-cleanup/source.wav"),
            frequency: 330
        )
        let imported = try await manager.importAudio(from: source)
        let editor = LabelingDetailEditor(file: imported, corpus: manager)
        editor.isDiagnosticsLoading = true
        editor.diagnosticsProgress = 0.4

        editor.cleanup()

        #expect(editor.isDiagnosticsLoading == false)
        #expect(editor.diagnosticsProgress == nil)
    }

    @Test
    func actorOwnedAudioPlayerPreparesSeeksAndReleases() async throws {
        let baseDirectory = try makeTempDirectory()
        let audioURL = try makeWAVFile(
            at: baseDirectory.appending(path: "playback/source.wav"),
            frequency: 330
        )
        let session = AudioPlaybackSession()

        try await session.prepare(url: audioURL)
        #expect(await session.isPrepared)

        await session.seek(to: 0.75)
        #expect(abs(await session.currentTime() - 0.75) < 0.05)

        await session.cleanup()
        #expect(!(await session.isPrepared))
    }

    @Test
    func backgroundToneAnalysisFindsAChangeBeneathCenteredNarration() throws {
        let baseDirectory = try makeTempDirectory()
        let audioURL = try makeStereoToneChangeWAV(
            at: baseDirectory.appending(path: "tone-change/source.wav"),
            changeTime: 12,
            duration: 24
        )

        let analysis = try BackgroundToneAnalyzer.analyze(
            audioURL: audioURL,
            configuration: .init(
                frameDuration: 1,
                kernelSize: 6,
                minimumCandidateSpacing: 4,
                edgeExclusion: 3,
                minimumNovelty: 0.05,
                minimumProminence: 0.02
            )
        )

        let nearest = try #require(
            analysis.candidates.min { abs($0.time - 12) < abs($1.time - 12) }
        )
        #expect(abs(nearest.time - 12) <= 1)
    }

    @Test
    func backgroundToneAnalysisDoesNotInventAChangeInASteadyBed() throws {
        let baseDirectory = try makeTempDirectory()
        let audioURL = try makeStereoToneChangeWAV(
            at: baseDirectory.appending(path: "steady-tone/source.wav"),
            changeTime: 30,
            duration: 24
        )

        let analysis = try BackgroundToneAnalyzer.analyze(
            audioURL: audioURL,
            configuration: .init(
                frameDuration: 1,
                kernelSize: 6,
                minimumCandidateSpacing: 4,
                edgeExclusion: 3,
                minimumNovelty: 0.05,
                minimumProminence: 0.02
            )
        )

        #expect(analysis.candidates.isEmpty)
    }

    @Test
    @MainActor
    func editorKeepsBackgroundToneCandidatesSeparateFromSavedBoundaries() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeStereoToneChangeWAV(
            at: baseDirectory.appending(path: "editor-tone-change/source.wav"),
            changeTime: 12,
            duration: 24
        )
        let imported = try await manager.importAudio(from: source)
        let editor = LabelingDetailEditor(file: imported, corpus: manager)

        await editor.analyzeBackgroundTones(
            configuration: .init(
                frameDuration: 1,
                kernelSize: 6,
                minimumCandidateSpacing: 4,
                edgeExclusion: 3,
                minimumNovelty: 0.05,
                minimumProminence: 0.02
            )
        )

        #expect(editor.backgroundToneCandidates.isEmpty == false)
        #expect(editor.boundaryCount == 0)
        #expect(editor.saveState == .saved)
    }

    @Test
    @MainActor
    func analyzerReviewCannotBeginBeforeBlindLabelsAreCompleteAndSaved() throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let unlabeled = LabelingDetailEditor(file: makeFile(phases: []), corpus: manager)

        #expect(!unlabeled.canEnterAnalyzerReview)
        #expect(!unlabeled.enterAnalyzerReview())
        #expect(!unlabeled.isAnalyzerReviewMode)

        let labeled = LabelingDetailEditor(
            file: makeFile(phases: [
                .init(phase: .induction, startTime: 0, endTime: 60)
            ]),
            corpus: manager
        )

        #expect(labeled.canEnterAnalyzerReview)
        #expect(labeled.enterAnalyzerReview())
        #expect(labeled.isAnalyzerReviewMode)
    }

    @Test
    @MainActor
    func blindLabelingDoesNotExposeStoredAnalyzerCandidates() throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let editor = LabelingDetailEditor(
            file: makeFile(phases: [
                .init(phase: .induction, startTime: 0, endTime: 60)
            ]),
            corpus: manager
        )
        editor.backgroundToneAnalysis = BackgroundToneAnalysis(
            candidates: [.init(time: 10, strength: 0.8)],
            novelty: [],
            source: .fullMix,
            analyzedDuration: 60
        )

        #expect(editor.transitionCandidates.isEmpty)
        #expect(editor.enterAnalyzerReview())
        #expect(editor.transitionCandidates.map(\.time) == [10])
    }

    @Test
    @MainActor
    func suggestedPhaseRowsRepairDuplicateAnalyzerSegmentIDs() throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let editor = LabelingDetailEditor(file: makeFile(phases: []), corpus: manager)
        let splitSourceID = UUID()
        editor.suggestedPhaseTimeline = .init(
            windows: [],
            segments: [
                PhaseSegment(
                    id: splitSourceID,
                    phase: .induction,
                    startTime: 0,
                    endTime: 30,
                    characteristics: "Induction",
                    tranceDepthEstimate: 0.3
                ),
                PhaseSegment(
                    id: splitSourceID,
                    phase: .suggestions,
                    startTime: 30,
                    endTime: 60,
                    characteristics: "Suggestions",
                    tranceDepthEstimate: 0.72
                )
            ]
        )

        let rows = editor.suggestedPhaseSegments

        #expect(rows.map(\.phase) == [.induction, .suggestions])
        #expect(rows.map(\.startTime) == [0, 30])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test
    @MainActor
    func analyzerReviewLocksTheBlindTimelineAgainstEdits() throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let editor = LabelingDetailEditor(
            file: makeFile(phases: [
                .init(phase: .induction, startTime: 0, endTime: 20),
                .init(phase: .deepening, startTime: 20, endTime: 60)
            ]),
            corpus: manager
        )
        let originalIDs = editor.labelingSegments.map(\.id)
        #expect(editor.enterAnalyzerReview())

        editor.currentTime = 10
        editor.markBoundaryAtPlayhead()
        editor.movePhasePoint(id: originalIDs[1], to: 30)
        editor.setPhase(ofPointID: originalIDs[0], to: .emergence)
        editor.deletePhasePoint(id: originalIDs[1])
        editor.clearAllPhases()

        #expect(editor.labelingSegments.map(\.id) == originalIDs)
        #expect(editor.labelingSegments.map(\.startTime) == [0, 20])
        #expect(editor.labelingSegments.map(\.phase) == [.induction, .deepening])
        #expect(editor.saveState == .saved)
    }

    @Test
    @MainActor
    func agreeingWithAReviewedCandidatePreservesTheBlindTimelineAndAdvances() throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let editor = LabelingDetailEditor(
            file: makeFile(phases: [
                .init(phase: .induction, startTime: 0, endTime: 20),
                .init(phase: .deepening, startTime: 20, endTime: 60)
            ]),
            corpus: manager
        )
        editor.backgroundToneAnalysis = BackgroundToneAnalysis(
            candidates: [
                .init(time: 10, strength: 0.8),
                .init(time: 30, strength: 0.7)
            ],
            novelty: [],
            source: .fullMix,
            analyzedDuration: 60
        )
        #expect(editor.enterAnalyzerReview())

        editor.jumpToNextTransitionCandidate()
        let acceptedID = try #require(editor.selectedTransitionCandidate?.id)
        editor.acceptSelectedTransitionCandidate()

        #expect(editor.labelingSegments.map(\.startTime) == [0, 20])
        #expect(editor.labelingSegments.map(\.phase) == [.induction, .deepening])
        #expect(editor.candidateDecision(for: acceptedID) == .accepted)
        #expect(editor.selectedTransitionCandidate?.time == 30)
    }

    @Test
    @MainActor
    func dismissingAReviewedCandidatePersistsWithoutResavingTheBlindLabels() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let recoveryStore = LabelingDraftRecoveryStore()
        let file = makeFile(phases: [
            .init(phase: .induction, startTime: 0, endTime: 60)
        ])
        let analysis = BackgroundToneAnalysis(
            candidates: [.init(time: 10, strength: 0.8)],
            novelty: [],
            source: .fullMix,
            analyzedDuration: 60
        )
        let editor = LabelingDetailEditor(
            file: file,
            corpus: manager,
            recoveryStore: recoveryStore
        )
        editor.backgroundToneAnalysis = analysis
        #expect(editor.enterAnalyzerReview())
        editor.jumpToNextTransitionCandidate()
        let dismissedID = try #require(editor.selectedTransitionCandidate?.id)

        editor.dismissSelectedTransitionCandidate()
        let recoveryURL = manager.analyzerDatasetDirectory
            .deletingLastPathComponent()
            .appending(path: "LabelingDrafts/\(file.id.uuidString).json")
        try await waitUntil { FileManager.default.fileExists(atPath: recoveryURL.path()) }

        #expect(editor.labelingSegments.map(\.phase) == [.induction])
        #expect(editor.saveState == .saved)
        #expect(editor.candidateDecision(for: dismissedID) == .dismissed)

        let reopened = LabelingDetailEditor(
            file: file,
            corpus: manager,
            recoveryStore: LabelingDraftRecoveryStore()
        )
        reopened.backgroundToneAnalysis = analysis
        await reopened.restoreWorkInProgressIfAvailable()

        #expect(reopened.isAnalyzerReviewMode)
        #expect(reopened.labelingSegments.map(\.phase) == [.induction])
        #expect(reopened.candidateDecision(for: dismissedID) == .dismissed)
        #expect(reopened.pendingTransitionCandidates.isEmpty)
    }

    @Test
    func reviewedCandidateIdentityDoesNotDependOnThePredictedPhase() {
        let deepening = TransitionCandidateReview.Candidate(
            source: .semantic,
            time: 25,
            confidence: 0.7,
            suggestedPhase: .deepening
        )
        let suggestions = TransitionCandidateReview.Candidate(
            source: .semantic,
            time: 25,
            confidence: 0.8,
            suggestedPhase: .suggestions
        )

        #expect(deepening.id == suggestions.id)
    }

    @Test
    @MainActor
    func candidateDecisionsReloadWithoutMakingCompletedLabelsLookUnsaved() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let file = makeFile(phases: [
            .init(phase: .induction, startTime: 0, endTime: 60)
        ])
        let candidate = TransitionCandidateReview.Candidate(
            source: .backgroundTone,
            time: 10,
            confidence: 0.8
        )
        let work = LabelingWorkInProgress(
            updatedAt: file.labeledAt.addingTimeInterval(1),
            file: file,
            labeling: TransitionLabelingDraft(duration: 60, phases: file.phases),
            candidateReviews: [
                .init(
                    candidateID: candidate.id,
                    decision: .dismissed,
                    decidedAt: file.labeledAt.addingTimeInterval(1),
                    boundaryTime: nil
                )
            ]
        )
        let recoveryDirectory = manager.analyzerDatasetDirectory
            .deletingLastPathComponent()
            .appending(path: "LabelingDrafts")
        try await LabelingDraftRecoveryStore().persist(work, in: recoveryDirectory)

        let editor = LabelingDetailEditor(
            file: file,
            corpus: manager,
            recoveryStore: LabelingDraftRecoveryStore()
        )
        editor.backgroundToneAnalysis = BackgroundToneAnalysis(
            candidates: [.init(time: 10, strength: 0.8)],
            novelty: [],
            source: .fullMix,
            analyzedDuration: 60
        )
        await editor.restoreWorkInProgressIfAvailable()

        #expect(editor.candidateDecision(for: candidate.id) == .dismissed)
        #expect(editor.saveState == .saved)
        #expect(editor.labelingSegments.map(\.phase) == [.induction])
    }

    @Test
    @MainActor
    func editorKeepsSemanticWindowsSeparateFromSavedLabels() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let file = makeFile(phases: [])
        let editor = LabelingDetailEditor(file: file, corpus: manager)
        editor.transcription = AudioTranscriptionResult(
            fullText: "it is safe to let everything go",
            segments: [
                .init(
                    text: "it is safe to let everything go",
                    timestamp: 0,
                    duration: 8,
                    confidence: -0.2
                )
            ],
            duration: 8,
            detectedLanguage: "en"
        )
        let examples = [
            SemanticPhaseAnalyzer.Example(
                phase: .deepening,
                text: "you can allow yourself to relax",
                position: 0.5
            )
        ]

        await editor.analyzeSemanticWindows(examples: examples)

        #expect(editor.semanticPhaseAnalysis?.windows.isEmpty == false)
        #expect(editor.boundaryCount == 0)
        #expect(editor.saveState == .saved)
    }

    @Test
    func legacyCorpusJSONDecodesIntoNewAudioFields() throws {
        let json = """
        {
          "id": "D7C0DB3C-4C62-45CE-B521-3122C994A2C1",
          "version": 1,
          "audioFilename": "legacy.wav",
          "audioDuration": 42.0,
          "audioSHA256": "abc123",
          "expectedContentType": "hypnosis",
          "expectedFrequencyBand": {
            "lower": 0.5,
            "upper": 8.0
          },
          "phases": [],
          "techniques": [],
          "labeledAt": "2026-04-01T00:00:00Z",
          "labelerNotes": ""
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(LabeledFile.self, from: Data(json.utf8))

        #expect(file.originalFilename == "legacy.wav")
        #expect(file.storedAudioFilename == "legacy.wav")
        #expect(file.audioFilename == "legacy.wav")
    }

    @Test
    func phaseValidationRejectsGapsAndOverlaps() throws {
        let base = makeFile(phases: [
            .init(phase: .preTalk, startTime: 0, endTime: 10),
            .init(phase: .induction, startTime: 12, endTime: 20)
        ])

        do {
            _ = try base.validatedForPersistence()
            Issue.record("Expected a phase gap validation failure.")
        } catch let error as LabeledFile.ValidationError {
            #expect(error == .phaseGap(index: 1, previousEnd: 10, nextStart: 12))
        }

        let overlapping = makeFile(phases: [
            .init(phase: .preTalk, startTime: 0, endTime: 10),
            .init(phase: .induction, startTime: 9, endTime: 20)
        ])

        do {
            _ = try overlapping.validatedForPersistence()
            Issue.record("Expected a phase overlap validation failure.")
        } catch let error as LabeledFile.ValidationError {
            #expect(error == .phaseOverlap(index: 1, previousEnd: 10, nextStart: 9))
        }
    }

    @Test
    @MainActor
    func importUsesUniqueStoredFilenamesAndDeleteOnlyRemovesUnreferencedAudio() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)

        let sourceA = try makeWAVFile(
            at: baseDirectory.appending(path: "A/clip.wav"),
            frequency: 220
        )
        let sourceB = try makeWAVFile(
            at: baseDirectory.appending(path: "B/clip.wav"),
            frequency: 440
        )

        let first = try await manager.importAudio(from: sourceA)
        let second = try await manager.importAudio(from: sourceB)

        #expect(first.originalFilename == "clip.wav")
        #expect(second.originalFilename == "clip.wav")
        #expect(first.storedAudioFilename != second.storedAudioFilename)

        let secondURL = manager.audioURL(for: second)
        #expect(FileManager.default.fileExists(atPath: secondURL.path()))

        try await manager.delete(first)

        #expect(!FileManager.default.fileExists(atPath: manager.audioURL(for: first).path()))
        #expect(FileManager.default.fileExists(atPath: secondURL.path()))
    }

    @Test
    @MainActor
    func saveMergesAgainstLatestStoredMetadata() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "merge/source.wav"),
            frequency: 330
        )

        let imported = try await manager.importAudio(from: source)
        var edited = imported
        edited.originalFilename = "mutated.wav"
        edited.storedAudioFilename = "different.wav"
        edited.audioSHA256 = "tampered"
        edited.audioDuration = 1
        edited.labelerNotes = "edited"

        let saved = try await manager.save(edited)

        #expect(saved.originalFilename == imported.originalFilename)
        #expect(saved.storedAudioFilename == imported.storedAudioFilename)
        #expect(saved.audioSHA256 == imported.audioSHA256)
        #expect(saved.audioDuration == imported.audioDuration)
        #expect(saved.labelerNotes == "edited")
    }

    @Test
    @MainActor
    func corpusNormalizationForcesHypnosisContentType() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "normalize/source.wav"),
            frequency: 330
        )

        let imported = try await manager.importAudio(from: source)
        var edited = imported
        edited.expectedContentType = .asmr
        edited.phases = [
            .init(phase: .preTalk, startTime: 0, endTime: imported.audioDuration)
        ]

        let saved = try await manager.save(edited)
        #expect(saved.expectedContentType == .hypnosis)

        await manager.reload()
        #expect(manager.labeledFiles.first?.expectedContentType == .hypnosis)

        let dataset = try AnalyzerOptimizationDataset.load(from: baseDirectory)
        #expect(dataset.examples.first?.example.labels.contentType == .hypnosis)
    }

    @Test
    @MainActor
    func importedUnlabeledAudioIsExcludedFromAnalyzerDataset() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "dataset/unlabeled.wav"),
            frequency: 330
        )

        _ = try await manager.importAudio(from: source)

        let datasetIndexURL = manager.analyzerDatasetIndexURL
        let datasetManifestURL = manager.analyzerDatasetManifestURL

        #expect(FileManager.default.fileExists(atPath: datasetIndexURL.path()))
        #expect(FileManager.default.fileExists(atPath: datasetManifestURL.path()))
        #expect((try String(contentsOf: datasetIndexURL)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            AnalyzerDatasetManifest.self,
            from: Data(contentsOf: datasetManifestURL)
        )
        let dataset = try AnalyzerOptimizationDataset.load(from: baseDirectory)

        #expect(manifest.exampleCount == 0)
        #expect(manifest.exampleFiles.isEmpty)
        #expect(dataset.examples.isEmpty)
        #expect(dataset.issues.isEmpty)
    }

    @Test
    @MainActor
    func batchFolderImportLabelsAudioFilesAsOnePhaseAndSkipsUnsupportedFiles() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let sourceDirectory = baseDirectory.appending(path: ".inductions", directoryHint: .isDirectory)
        let first = try makeWAVFile(at: sourceDirectory.appending(path: "deepener-a.wav"), frequency: 220)
        let second = try makeWAVFile(at: sourceDirectory.appending(path: "deepener-b.wav"), frequency: 440)
        let nested = try makeWAVFile(at: sourceDirectory.appending(path: "nested/deepener-c.wav"), frequency: 550)
        try Data("not audio".utf8).write(to: sourceDirectory.appending(path: "notes.txt"), options: .atomic)
        try Data("not audio".utf8).write(to: sourceDirectory.appending(path: "nested/readme.md"), options: .atomic)

        let result = try await manager.importAudioFolder(from: sourceDirectory, labeledAs: .deepening)

        #expect(result.importedFiles.map(\.originalFilename) == [
            first.lastPathComponent,
            second.lastPathComponent,
            nested.lastPathComponent
        ])
        #expect(result.skippedFilenames == ["nested/readme.md", "notes.txt"])
        #expect(manager.labeledFiles.count == 3)

        for file in result.importedFiles {
            let phase = try #require(file.phases.first)
            #expect(file.phases.count == 1)
            #expect(phase.phase == .deepening)
            #expect(phase.startTime == 0)
            #expect(abs(phase.endTime - file.audioDuration) < 0.001)
            #expect(file.labelerNotes.contains("Silver label"))
        }

        let dataset = try AnalyzerOptimizationDataset.load(from: baseDirectory)
        #expect(dataset.examples.count == 3)
        #expect(dataset.examples.allSatisfy { $0.example.labels.phaseOrder == [.deepening] })
    }

    @Test
    func trancePhaseExpansionHasStableOrderAndNames() {
        #expect(TrancePhase.orderedHypnosisPhases == [
            .induction, .fractionation, .deepening, .suggestions,
            .brainwashing, .conditioning, .emergence
        ])

        #expect(TrancePhase.fractionation.displayName == "Fractionation")
        #expect(TrancePhase.confusion.displayName == "Confusion")
        #expect(TrancePhase.suggestions.displayName == "Suggestions")
        #expect(TrancePhase.brainwashing.displayName == "Brainwashing")
        // Folded away only where the light is identical or near-identical.
        #expect(TrancePhase.preTalk.labelingPhase == .induction)
        #expect(TrancePhase.confusion.labelingPhase == .deepening)
        #expect(TrancePhase.therapy.labelingPhase == .suggestions)
        #expect(TrancePhase.eroticSuggestions.labelingPhase == .suggestions)

        // Target phases in their own right — their light differs materially.
        #expect(TrancePhase.fractionation.labelingPhase == .fractionation)
        #expect(TrancePhase.conditioning.labelingPhase == .conditioning)
    }

    @Test
    /// See `techniquePhasesSurviveStorageAndProjectToDeepening`. Losing these
    /// three on save is what cost the training corpus roughly 40% of its phase
    /// identities, including every `pre_talk → induction` transition.
    func contentSpecificPhasesSurviveStorageAndProjectToSuggestions() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        for rawValue in ["therapeutic_work", "erotic_suggestions", "post_hypnotic_conditioning"] {
            let decoded = try decoder.decode(TrancePhase.self, from: Data("\"\(rawValue)\"".utf8))
            #expect(decoded.rawValue == rawValue)
            // conditioning is now a target phase; therapy and erotic still fold
            // into suggestions, the nearest target by trance depth.
            #expect(decoded.labelingPhase == (decoded == .conditioning ? .conditioning : .suggestions))

            let encoded = try String(data: encoder.encode(decoded), encoding: .utf8)
            #expect(encoded == "\"\(rawValue)\"")
        }
    }

    @Test
    /// Rewritten when the collapse moved out of the codec. Storage now keeps the
    /// phase that was labelled, and `labelingPhase` projects to the five-bucket
    /// view where light is chosen. The old version asserted that decoding
    /// "fractionation" produced `.deepening`, which is exactly the behaviour that
    /// made SessionGenerator's fractionation contour unreachable.
    func techniquePhasesSurviveStorageAndProjectToDeepening() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        for rawValue in ["fractionation", "confusion"] {
            let decoded = try decoder.decode(TrancePhase.self, from: Data("\"\(rawValue)\"".utf8))
            #expect(decoded.rawValue == rawValue)
            // fractionation is now a target phase in its own right; confusion
            // still folds into deepening because their light is identical.
            #expect(decoded.labelingPhase == (decoded == .fractionation ? .fractionation : .deepening))

            let encoded = try String(data: encoder.encode(decoded), encoding: .utf8)
            #expect(encoded == "\"\(rawValue)\"")
        }
    }

    @Test
    @MainActor
    func saveCanonicalizesLegacyContentPhasesInAnalyzerDataset() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "expanded/source.wav"),
            frequency: 220
        )

        let imported = try await manager.importAudio(from: source)
        let duration = imported.audioDuration
        let quarter = duration / 4
        var labeled = imported
        labeled.phases = [
            .init(phase: .induction, startTime: 0, endTime: quarter),
            .init(phase: .fractionation, startTime: quarter, endTime: quarter * 2),
            .init(phase: .eroticSuggestions, startTime: quarter * 2, endTime: quarter * 3),
            .init(phase: .brainwashing, startTime: quarter * 3, endTime: duration)
        ]

        _ = try await manager.save(labeled)
        let dataset = try AnalyzerOptimizationDataset.load(from: baseDirectory)
        let phases = dataset.examples.first?.example.labels.phaseSegments.map(\.phase) ?? []

        // fractionation now survives the projection — collapsing it lost a
        // unique light contour and moved trance depth 0.42 → 0.62. erotic
        // suggestions still folds into suggestions, a 0.06 depth difference.
        #expect(phases == [.induction, .fractionation, .suggestions, .brainwashing])
    }

    @Test
    @MainActor
    func saveWritesAnalyzerDatasetWithAudioAndTimeline() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let source = try makeWAVFile(
            at: baseDirectory.appending(path: "dataset/source.wav"),
            frequency: 330
        )

        let imported = try await manager.importAudio(from: source)
        var labeled = imported
        let midpoint = imported.audioDuration / 2
        labeled.phases = [
            .init(phase: .preTalk, startTime: 0, endTime: midpoint),
            .init(phase: .suggestions, startTime: midpoint, endTime: imported.audioDuration)
        ]
        labeled.labelerNotes = "Ground truth export"

        let saved = try await manager.save(labeled)

        let datasetIndexURL = manager.analyzerDatasetIndexURL
        let datasetManifestURL = manager.analyzerDatasetManifestURL
        let datasetAudioURL = manager.analyzerDatasetDirectory
            .appending(path: "audio")
            .appending(path: saved.storedAudioFilename)

        #expect(FileManager.default.fileExists(atPath: datasetIndexURL.path()))
        #expect(FileManager.default.fileExists(atPath: datasetManifestURL.path()))
        #expect(FileManager.default.fileExists(atPath: datasetAudioURL.path()))

        let datasetLines = try String(contentsOf: datasetIndexURL)
            .split(separator: "\n")
            .map(String.init)
        #expect(datasetLines.count == 1)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let example = try decoder.decode(
            AnalyzerTrainingExample.self,
            from: Data(datasetLines[0].utf8)
        )
        let manifest = try decoder.decode(
            AnalyzerDatasetManifest.self,
            from: Data(contentsOf: datasetManifestURL)
        )

        #expect(example.exampleID == saved.id)
        #expect(example.audio.datasetRelativePath == "audio/\(saved.storedAudioFilename)")
        #expect(example.labels.phasePoints.count == 2)
        #expect(example.labels.phaseSegments.count == 2)
        #expect(example.labels.hasCompletePhaseCoverage)
        #expect(example.labels.labelerNotes == "Ground truth export")
        // The export carries the vocabulary the analyzer is trained to emit, so
        // pre_talk arrives as induction — their light is identical, and training
        // on a label the analyzer is never asked to produce would teach it
        // something to unteach later. The labeller's own choice is preserved in
        // the corpus file, not here.
        #expect(example.labels.denseTimeline.contains { $0.phase == .induction })
        #expect(example.labels.denseTimeline.contains { $0.phase == .preTalk } == false)
        #expect(example.labels.denseTimeline.contains { $0.phase == .suggestions })
        #expect(manifest.exampleCount == 1)
        #expect(manifest.exampleFiles == ["examples/\(saved.id.uuidString).json"])
    }

    @Test
    func transcriptInsightSummarizesSectionWordsAndRate() throws {
        let transcription = AudioTranscriptionResult(
            fullText: "relax deeper relax drift deeper relax calm calm focus",
            segments: [
                .init(text: "relax deeper relax", timestamp: 0, duration: 3, confidence: -0.2),
                .init(text: "drift deeper relax", timestamp: 3, duration: 3, confidence: -0.3),
                .init(text: "calm calm focus", timestamp: 6, duration: 3, confidence: -0.4)
            ],
            duration: 9,
            detectedLanguage: "en"
        )

        let insight = try #require(
            LabelingDetailEditor.makeTranscriptInsight(
                id: UUID(),
                phase: .deepening,
                startTime: 0,
                endTime: 9,
                transcription: transcription
            )
        )

        #expect(insight.wordCount == 9)
        #expect(insight.uniqueWordCount == 5)
        #expect(insight.wordsPerMinute == 60)
        #expect(insight.excerpts.count == 3)
        #expect(insight.topWords.prefix(3).map(\.word) == ["relax", "calm", "deeper"])
        #expect(insight.topWords.prefix(3).map(\.count) == [3, 2, 2])
    }

    @Test
    func transcriptInsightClipsToSelectedPhaseWindow() throws {
        let transcription = AudioTranscriptionResult(
            fullText: "begin settle deeper deeper awake again",
            segments: [
                .init(text: "begin settle", timestamp: 0, duration: 2, confidence: -0.2),
                .init(text: "deeper deeper", timestamp: 2, duration: 2, confidence: -0.2),
                .init(text: "awake again", timestamp: 4, duration: 2, confidence: -0.2)
            ],
            duration: 6,
            detectedLanguage: "en"
        )

        let insight = try #require(
            LabelingDetailEditor.makeTranscriptInsight(
                id: UUID(),
                phase: .deepening,
                startTime: 1.5,
                endTime: 4.5,
                transcription: transcription
            )
        )

        #expect(insight.excerpts.count == 3)
        #expect(insight.wordCount == 6)
        #expect(insight.topWords.first?.word == "deeper")
        #expect(insight.topWords.first?.count == 2)
        #expect(insight.longestPause == 0)
    }

    @Test
    func semanticWindowMatchesAParaphraseWithoutSharedKeywords() throws {
        let analyzer = SemanticPhaseAnalyzer(examples: [
            .init(
                phase: .deepening,
                text: "you can allow yourself to relax",
                position: 0.5
            ),
            .init(
                phase: .emergence,
                text: "open your eyes and wake up now",
                position: 0.5
            )
        ])
        let transcription = AudioTranscriptionResult(
            fullText: "it is safe to let everything go",
            segments: [
                .init(
                    text: "it is safe to let everything go",
                    timestamp: 0,
                    duration: 8,
                    confidence: -0.2
                )
            ],
            duration: 8,
            detectedLanguage: "en"
        )

        let analysis = try analyzer.analyze(transcription: transcription)
        let window = try #require(analysis.windows.first)

        #expect(window.phase == .deepening)
        #expect(window.matchedExampleText == "you can allow yourself to relax")
        #expect(window.confidence > 0.5)
    }

    @Test
    func semanticAnalysisBuildsOverlappingWordWindows() throws {
        let analyzer = SemanticPhaseAnalyzer(
            examples: [
                .init(phase: .deepening, text: "sink further into calm", position: 0.25),
                .init(phase: .emergence, text: "return awake and alert", position: 0.85)
            ],
            configuration: .init(windowWordCount: 5, windowStride: 3)
        )
        let transcription = AudioTranscriptionResult(
            fullText: "one two three four five six seven eight nine ten eleven twelve",
            segments: [
                .init(text: "one two three four", timestamp: 0, duration: 4, confidence: -0.2),
                .init(text: "five six seven eight", timestamp: 4, duration: 4, confidence: -0.2),
                .init(text: "nine ten eleven twelve", timestamp: 8, duration: 4, confidence: -0.2)
            ],
            duration: 12,
            detectedLanguage: "en"
        )

        let windows = try analyzer.analyze(transcription: transcription).windows

        #expect(windows.count == 4)
        #expect(windows.map(\.startTime) == [0, 3, 6, 7])
        #expect(windows.map(\.endTime) == [5, 8, 11, 12])
        #expect(windows.first?.text == "one two three four five")
        #expect(windows.last?.text == "eight nine ten eleven twelve")
    }

    @Test
    func semanticAnalysisUsesLabeledCorpusExamples() throws {
        let knowledge = CorpusPhaseKnowledge(
            fewShotExamples: [
                .init(
                    text: "opening and closing your eyes carries you further each time",
                    position: 0.3,
                    correctPhase: TrancePhase.fractionation.rawValue
                )
            ]
        )
        let analyzer = SemanticPhaseAnalyzer(corpusKnowledge: knowledge)
        let transcription = AudioTranscriptionResult(
            fullText: "each cycle of waking and drifting takes you farther",
            segments: [
                .init(
                    text: "each cycle of waking and drifting takes you farther",
                    timestamp: 0,
                    duration: 8,
                    confidence: -0.2
                )
            ],
            duration: 8,
            detectedLanguage: "en"
        )

        let analysis = try analyzer.analyze(transcription: transcription)
        let window = try #require(analysis.windows.first)

        #expect(analysis.exampleCount == 1)
        #expect(window.phase == .fractionation)
    }

    @Test
    func semanticWindowsCollapseIntoATentativeTimeline() throws {
        let analyzer = SemanticPhaseAnalyzer(
            examples: [
                .init(
                    phase: .deepening,
                    text: "sink gently downward into stillness",
                    position: 0.25
                ),
                .init(
                    phase: .emergence,
                    text: "open eyes feeling awake now",
                    position: 0.75
                )
            ],
            configuration: .init(
                windowWordCount: 5,
                windowStride: 5,
                positionPenalty: 0
            ),
            semanticDistance: { window, example in
                let bothAreDeepening = window.hasPrefix("sink") && example.hasPrefix("sink")
                let bothAreEmergence = window.hasPrefix("open") && example.hasPrefix("open")
                return bothAreDeepening || bothAreEmergence ? 0 : 1
            }
        )
        let transcription = AudioTranscriptionResult(
            fullText: "sink gently downward into stillness open eyes feeling awake now",
            segments: [
                .init(
                    text: "sink gently downward into stillness",
                    timestamp: 0,
                    duration: 5,
                    confidence: -0.2
                ),
                .init(
                    text: "open eyes feeling awake now",
                    timestamp: 5,
                    duration: 5,
                    confidence: -0.2
                )
            ],
            duration: 10,
            detectedLanguage: "en"
        )

        let segments = try analyzer.analyze(transcription: transcription).segments

        #expect(segments.map(\.phase) == [.deepening, .emergence])
        #expect(segments.map(\.startTime) == [0, 5])
        #expect(segments.map(\.endTime) == [5, 10])
        #expect(segments.map(\.windowCount) == [1, 1])
    }

    @Test
    func semanticTimelineIgnoresASingleWindowPhaseBlip() throws {
        let analyzer = SemanticPhaseAnalyzer(
            examples: [
                .init(phase: .deepening, text: "deep example", position: 0.5),
                .init(phase: .emergence, text: "awake example", position: 0.5)
            ],
            configuration: .init(
                windowWordCount: 2,
                windowStride: 2,
                positionPenalty: 0
            ),
            semanticDistance: { window, example in
                let windowIsAwake = window.hasPrefix("awake")
                let exampleIsAwake = example.hasPrefix("awake")
                return windowIsAwake == exampleIsAwake ? 0 : 1
            }
        )
        let transcription = AudioTranscriptionResult(
            fullText: "deep one deep two awake blip deep three deep four",
            segments: [
                .init(
                    text: "deep one deep two awake blip deep three deep four",
                    timestamp: 0,
                    duration: 10,
                    confidence: -0.2
                )
            ],
            duration: 10,
            detectedLanguage: "en"
        )

        let segments = try analyzer.analyze(transcription: transcription).segments

        #expect(segments.count == 1)
        #expect(segments.first?.phase == .deepening)
        #expect(segments.first?.windowCount == 5)
    }

    @Test
    func semanticCorpusExamplesExcludeTheFileBeingAnalyzed() {
        let excludedID = UUID()
        let retainedID = UUID()
        let sources = [
            SemanticPhaseExampleStore.Source(
                id: excludedID,
                filename: "excluded.mp3",
                duration: 10,
                phaseSegments: [
                    .init(
                        id: UUID(),
                        phase: .deepening,
                        startTime: 0,
                        endTime: 10,
                        durationSeconds: 10,
                        notes: nil
                    )
                ],
                transcription: .init(
                    fullText: "sink into calm",
                    segments: [
                        .init(text: "sink into calm", timestamp: 0, duration: 10, confidence: -0.2)
                    ],
                    duration: 10,
                    detectedLanguage: "en"
                )
            ),
            SemanticPhaseExampleStore.Source(
                id: retainedID,
                filename: "retained.mp3",
                duration: 10,
                phaseSegments: [
                    .init(
                        id: UUID(),
                        phase: .emergence,
                        startTime: 0,
                        endTime: 10,
                        durationSeconds: 10,
                        notes: nil
                    )
                ],
                transcription: .init(
                    fullText: "return awake now",
                    segments: [
                        .init(text: "return awake now", timestamp: 0, duration: 10, confidence: -0.2)
                    ],
                    duration: 10,
                    detectedLanguage: "en"
                )
            )
        ]

        let examples = SemanticPhaseExampleStore.makeExamples(
            from: sources,
            excluding: excludedID
        )

        #expect(examples.count == 1)
        #expect(examples.first?.sourceExampleID == retainedID)
        #expect(examples.first?.phase == .emergence)
        #expect(examples.first?.text == "return awake now")
    }

    @Test
    @MainActor
    func semanticCorpusExamplesUseOnlyHumanGoldLabels() async throws {
        let baseDirectory = try makeTempDirectory()
        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        let goldSource = try makeWAVFile(
            at: baseDirectory.appending(path: "semantic-gold/source.wav"),
            frequency: 220
        )
        let silverSource = try makeWAVFile(
            at: baseDirectory.appending(path: "semantic-silver/source.wav"),
            frequency: 330
        )

        var gold = try await manager.importAudio(from: goldSource)
        gold.phases = [
            .init(phase: .deepening, startTime: 0, endTime: gold.audioDuration)
        ]
        gold.labelerNotes = "Human reviewed"
        gold = try await manager.save(gold)

        var silver = try await manager.importAudio(from: silverSource)
        silver.phases = [
            .init(phase: .suggestions, startTime: 0, endTime: silver.audioDuration)
        ]
        silver.labelerNotes = "\(BambiSafetyPolicy.silverLabelPrefix); not human reviewed."
        silver = try await manager.save(silver)

        try TranscriptCacheStore.save(
            AudioTranscriptionResult(
                fullText: "sink further into calm",
                segments: [
                    .init(
                        text: "sink further into calm",
                        timestamp: 0,
                        duration: gold.audioDuration,
                        confidence: -0.2
                    )
                ],
                duration: gold.audioDuration,
                detectedLanguage: "en"
            ),
            for: gold,
            in: manager.analyzerDatasetDirectory
        )
        try TranscriptCacheStore.save(
            AudioTranscriptionResult(
                fullText: "bambi accepts every suggestion",
                segments: [
                    .init(
                        text: "bambi accepts every suggestion",
                        timestamp: 0,
                        duration: silver.audioDuration,
                        confidence: -0.2
                    )
                ],
                duration: silver.audioDuration,
                detectedLanguage: "en"
            ),
            for: silver,
            in: manager.analyzerDatasetDirectory
        )

        let examples = try SemanticPhaseExampleStore.load(
            from: baseDirectory,
            excluding: nil
        )

        #expect(Set(examples.compactMap(\.sourceExampleID)) == [gold.id])
        #expect(examples.allSatisfy { $0.sourceFilename == gold.audioFilename })
        #expect(examples.contains { $0.text.localizedCaseInsensitiveContains("bambi") } == false)
    }

    @Test
    @MainActor
    func corruptedJSONIsReportedInsteadOfSilentlyDropped() async throws {
        let baseDirectory = try makeTempDirectory()
        let invalidJSONURL = baseDirectory.appending(path: "broken.json")
        try Data("{ invalid json".utf8).write(to: invalidJSONURL, options: .atomic)

        let manager = TrainingCorpusManager(baseDirectory: baseDirectory, autoLoad: false)
        await manager.reload()

        #expect(manager.labeledFiles.isEmpty)
        #expect(manager.lastLoadIssues.count == 1)
        #expect(manager.lastLoadIssues[0].filename == "broken.json")
    }

    private func makeFile(phases: [LabeledFile.LabeledPhase]) -> LabeledFile {
        LabeledFile(
            originalFilename: "sample.wav",
            storedAudioFilename: "stored.wav",
            audioDuration: 60,
            audioSHA256: "hash",
            expectedContentType: .hypnosis,
            expectedFrequencyBand: .init(lower: 0.5, upper: 8),
            phases: phases,
            techniques: [],
            labeledAt: Date(),
            labelerNotes: ""
        )
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeIsolatedUserDefaults() throws -> UserDefaults {
        let suiteName = "LumeLabelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw CocoaError(.coderInvalidValue)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while condition() == false, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func makeWAVFile(at url: URL, frequency: Double) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let sampleRate = 8_000
        let sampleCount = 16_000
        let bitsPerSample = 16
        let channels = 1
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = sampleCount * blockAlign

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(channels))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(byteRate))
        data.appendLE(UInt16(blockAlign))
        data.appendLE(UInt16(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.appendLE(UInt32(dataSize))

        for index in 0..<sampleCount {
            let theta = Double(index) / Double(sampleRate) * frequency * .pi * 2
            let sample = Int16((sin(theta) * 0.4 * Double(Int16.max)).rounded())
            data.appendLE(sample)
        }

        try data.write(to: url, options: .atomic)
        return url
    }

    private func makeStereoToneChangeWAV(
        at url: URL,
        changeTime: TimeInterval,
        duration: TimeInterval
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let sampleRate = 8_000
        let sampleCount = Int(duration * Double(sampleRate))
        let bitsPerSample = 16
        let channels = 2
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = sampleCount * blockAlign

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(channels))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(byteRate))
        data.appendLE(UInt16(blockAlign))
        data.appendLE(UInt16(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.appendLE(UInt32(dataSize))

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let narration = sin(time * 180 * .pi * 2) * 0.45
            let backgroundFrequency = time < changeTime ? 90.0 : 330.0
            let background = sin(time * backgroundFrequency * .pi * 2) * 0.25
            let left = Int16(
                (max(-1, min(1, narration + background)) * Double(Int16.max)).rounded()
            )
            let right = Int16(
                (max(-1, min(1, narration - background)) * Double(Int16.max)).rounded()
            )
            data.appendLE(left)
            data.appendLE(right)
        }

        try data.write(to: url, options: .atomic)
        return url
    }

}


private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(UnsafeBufferPointer(start: &littleEndian, count: 1))
    }

    mutating func appendLE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(UnsafeBufferPointer(start: &littleEndian, count: 1))
    }

    mutating func appendLE(_ value: Int16) {
        var littleEndian = value.littleEndian
        append(UnsafeBufferPointer(start: &littleEndian, count: 1))
    }
}
