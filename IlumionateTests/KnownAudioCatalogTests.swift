//
//  KnownAudioCatalogTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct KnownAudioCatalogTests {
    @Test func bundledCatalogLoadsGeneratedEntries() {
        #expect(KnownAudioCatalog.shared.entries.count == 54)
        #expect(KnownAudioCatalog.shared.entries.count { $0.transcript.isEmpty == false } == 45)
        #expect(KnownAudioCatalog.shared.entries.count { $0.contentFingerprints.isEmpty == false } == 35)
    }

    @Test func everyKnownTrackHasAVersionedGoldLightScore() {
        let entries = KnownAudioCatalog.shared.entries

        #expect(entries.allSatisfy { $0.goldLightScore.scoreVersion == 2 })
        #expect(entries.allSatisfy { $0.goldLightScore.moments.count >= 6 })
        #expect(entries.allSatisfy { $0.goldLightScore.designIntent.isEmpty == false })
        #expect(Set(entries.map(\.goldLightScore.sessionID)).count == entries.count)
        #expect(entries.count { $0.goldLightScore.transcriptAnchorCount > 0 } == 53)
    }

    @Test func everyGoldScoreCarriesConsistentEvidenceProvenance() {
        for entry in KnownAudioCatalog.shared.entries {
            let score = entry.goldLightScore

            #expect(
                score.transcriptAnchorCount == score.evidenceAnchors.count,
                "\(entry.title) has inconsistent evidence counts."
            )
            #expect(
                score.evidenceAnchors.allSatisfy { anchor in
                    anchor.cue.isEmpty == false
                        && anchor.position > 0
                        && anchor.position < 1
                        && score.moments.contains {
                            abs($0.position - anchor.position) < 0.0001
                        }
                },
                "\(entry.title) has evidence that is not represented in its timeline."
            )

            switch score.evidenceKind {
            case .communityTranscript:
                #expect(entry.transcript.isEmpty == false)
                #expect(score.evidenceAnchors.count >= 2)
            case .localAudioReview:
                #expect(score.timingBasis == .reviewedAudioTiming)
                #expect(score.evidenceAnchors.isEmpty == false)
            case .catalogMetadata:
                #expect(score.timingBasis == .intentOnly)
                #expect(score.evidenceAnchors.isEmpty)
            }
        }
    }

    @Test func everyCanonicalFilenameRecognizesItsOwningCatalogEntry() {
        for entry in KnownAudioCatalog.shared.entries {
            let file = AudioFile(
                filename: "\(entry.trackNumber) - \(entry.title).mp3",
                duration: 600,
                fileSize: 1_024
            )

            #expect(
                KnownAudioCatalog.shared.match(audioFile: file)?.entry.id == entry.id,
                "Canonical filename did not resolve to \(entry.title)."
            )
        }
    }

    @Test func contentFingerprintRecognizesSuppliedAudioAfterRename() throws {
        let entry = try #require(
            KnownAudioCatalog.shared.entries.first {
                $0.title == "Sleepyhead"
            }
        )
        let fingerprint = try #require(entry.contentFingerprints.first)
        let renamedFile = AudioFile(
            filename: "my completely renamed recording.mp3",
            duration: 490.031,
            fileSize: 1_024,
            contentFingerprint: fingerprint.uppercased()
        )

        let match = try #require(
            KnownAudioCatalog.shared.match(audioFile: renamedFile)
        )

        #expect(match.entry.id == entry.id)
        #expect(match.confidence == 1)
    }

    @Test func everyGoldTimelineIsOrderedBoundedAndComplete() {
        for entry in KnownAudioCatalog.shared.entries {
            let moments = entry.goldLightScore.moments
            let positions = moments.map(\.position)

            #expect(positions.first == 0, "\(entry.title) must begin at zero.")
            #expect(positions.last == 1, "\(entry.title) must end at one.")
            #expect(
                positions == positions.sorted() && Set(positions).count == positions.count,
                "\(entry.title) moments must be strictly ordered."
            )
            #expect(
                moments.allSatisfy {
                    $0.frequency > 0
                        && $0.frequency <= LightSafety.maxFlashHz
                        && (0...1).contains($0.intensity)
                },
                "\(entry.title) contains an out-of-bounds light moment."
            )
        }
    }

    @Test func canonicalFilenameResolvesTranscriptAndMetadata() throws {
        let file = AudioFile(
            filename: "01 - Instant Bimbo Sleepdoll.mp3",
            duration: 1_200,
            fileSize: 1_024
        )

        let match = try #require(KnownAudioCatalog.shared.match(audioFile: file))
        let transcription = try #require(
            KnownAudioCatalog.shared.transcription(for: file)
        )
        let metadata = try #require(
            KnownAudioCatalog.shared.verifiedMetadata(for: file)
        )

        #expect(match.entry.trackNumber == "01")
        #expect(match.confidence >= 0.98)
        #expect(transcription.fullText.count > 1_000)
        #expect(!transcription.segments.isEmpty)
        #expect(metadata.preferredTitle == "Instant Bimbo Sleepdoll")
    }

    @Test @MainActor
    func recognizedFilenameResolvesStableGoldSessionAtImportedDuration() throws {
        let file = AudioFile(
            filename: "01 - Instant Bimbo Sleepdoll.mp3",
            duration: 875.5,
            fileSize: 1_024
        )

        let first = try #require(
            KnownAudioCatalog.shared.goldLightSession(for: file)
        )
        let second = try #require(
            KnownAudioCatalog.shared.goldLightSession(for: file)
        )

        #expect(first.id == second.id)
        #expect(first.duration_sec == 875.5)
        #expect(first.light_score.first?.time == 0)
        #expect(first.light_score.last?.time == 875.5)
        #expect(first.light_score.allSatisfy { $0.time >= 0 && $0.time <= 875.5 })
        #expect(first.session_name == "Instant Bimbo Sleepdoll — Gold Light Score")
    }

    @Test @MainActor
    func goldScoresHonorPlaylistTransitionContracts() throws {
        let induction = try #require(
            KnownAudioCatalog.shared.goldLightSession(
                for: AudioFile(
                    filename: "01 - Bubble Induction.mp3",
                    duration: 1_200,
                    fileSize: 1_024
                )
            )
        )
        let awakener = try #require(
            KnownAudioCatalog.shared.goldLightSession(
                for: AudioFile(
                    filename: "10 - Bambi Awakens.mp3",
                    duration: 600,
                    fileSize: 1_024
                )
            )
        )
        let sleepener = try #require(
            KnownAudioCatalog.shared.goldLightSession(
                for: AudioFile(
                    filename: "08 - Bimbodoll Sleepener.mp3",
                    duration: 450,
                    fileSize: 1_024
                )
            )
        )

        #expect(induction.light_score.last?.frequency ?? .infinity < 6)
        #expect(awakener.light_score.last?.frequency ?? 0 >= 10)
        #expect(sleepener.light_score.last?.frequency ?? .infinity < 4)
    }

    @Test @MainActor
    func pleasurelockGoldScorePreservesReviewedWakeAndRedrop() throws {
        let duration = 3_954.050612
        let session = try #require(
            KnownAudioCatalog.shared.goldLightSession(
                for: AudioFile(
                    filename: "05 - Pleasurelock Bimbo Compliance Doll.mp3",
                    duration: duration,
                    fileSize: 1_024
                )
            )
        )
        let wakeMoment = try #require(
            session.light_score.first {
                abs($0.time - duration * 0.82) < 0.01
            }
        )
        let redropMoment = try #require(
            session.light_score.first {
                abs($0.time - duration * 0.90) < 0.01
            }
        )

        #expect(wakeMoment.frequency >= 9)
        #expect(wakeMoment.bilateral == false)
        #expect(redropMoment.frequency <= 5)
        #expect(redropMoment.bilateral == true)
        #expect(session.light_score.last?.frequency ?? .infinity < 7)
    }

    @Test @MainActor
    func bambiAwakensStaysDeepUntilReviewedFinalEmergence() throws {
        let duration = 591.046531
        let session = try #require(
            KnownAudioCatalog.shared.goldLightSession(
                for: AudioFile(
                    filename: "10 Bambi Awakens.mp3",
                    duration: duration,
                    fileSize: 1_024
                )
            )
        )
        let lateHold = try #require(
            session.light_score.first {
                abs($0.time - duration * 0.68) < 0.01
            }
        )
        let finalWake = try #require(
            session.light_score.first {
                abs($0.time - duration * 0.96) < 0.01
            }
        )

        #expect(lateHold.frequency < 5)
        #expect(finalWake.frequency >= 10)
        #expect(finalWake.bilateral == false)
    }

    @Test func catalogTimestampsProduceTimedSegments() throws {
        let file = AudioFile(
            filename: "00 - Rapid Induction.mp3",
            duration: 600,
            fileSize: 1_024
        )

        let transcription = try #require(
            KnownAudioCatalog.shared.transcription(for: file)
        )

        #expect(transcription.segments.count > 1)
        #expect(transcription.segments.first?.timestamp == 0)
    }

    @Test func unrelatedAudioRemainsInvisibleToCatalog() {
        let file = AudioFile(
            filename: "Evening Rain Meditation.m4a",
            duration: 900,
            fileSize: 1_024
        )

        #expect(KnownAudioCatalog.shared.match(audioFile: file) == nil)
        #expect(KnownAudioCatalog.shared.transcription(for: file) == nil)
        #expect(KnownAudioCatalog.shared.verifiedMetadata(for: file) == nil)
    }

    @Test @MainActor
    func unrelatedAudioDoesNotReceiveGoldLightScore() {
        let file = AudioFile(
            filename: "Evening Rain Meditation.m4a",
            duration: 900,
            fileSize: 1_024
        )

        #expect(KnownAudioCatalog.shared.goldLightSession(for: file) == nil)
    }

    @Test @MainActor
    func knownTrackWithoutBundledTranscriptStillReceivesGoldScore() {
        let file = AudioFile(
            filename: "05 - Pleasurelock Bimbo Compliance Doll.mp3",
            duration: 2_400,
            fileSize: 1_024
        )

        #expect(KnownAudioCatalog.shared.match(audioFile: file) != nil)
        #expect(KnownAudioCatalog.shared.transcription(for: file) == nil)
        #expect(KnownAudioCatalog.shared.goldLightSession(for: file) != nil)
    }

    @Test @MainActor
    func puppetPrincessLoopAutomaticallyReceivesReviewedGoldScore() throws {
        let file = AudioFile(
            filename: "04 Giggledoll.mp3",
            duration: 394.031,
            fileSize: 1_024
        )

        let match = try #require(KnownAudioCatalog.shared.match(audioFile: file))
        let session = try #require(
            KnownAudioCatalog.shared.goldLightSession(for: file)
        )

        #expect(match.entry.series == "Bambi Puppet Princess Loops")
        #expect(match.entry.goldLightScore.evidenceKind == .localAudioReview)
        #expect(session.session_name == "Giggledoll — Gold Light Score")
        #expect(session.light_score.last?.time == 394.031)
    }

    @Test func recognizedTrackMaterializesReviewedAnalysisWithoutOnDeviceAI() throws {
        let file = AudioFile(
            filename: "04 Giggledoll.mp3",
            duration: 394.031,
            fileSize: 1_024
        )

        let reviewed = try #require(
            KnownAudioCatalog.shared.reviewedAnalysis(for: file)
        )

        #expect(reviewed.contentType == .hypnosis)
        #expect(reviewed.recommendedPreset == "Giggledoll — Gold Light Score")
        #expect(reviewed.aiSummary.contains("reviewed gold light score"))
        #expect(reviewed.expertAnalysis?.verdict == .productionReady)
        #expect(reviewed.expertAnalysis?.qualityScore == 1)
        #expect(reviewed.hypnosisMetadata?.phases.isEmpty == false)
        #expect(reviewed.discoveredMetadata?.preferredTitle == "Giggledoll")
    }

    @Test func reviewedAnalysisUsesGoldTimingInsteadOfKeywordPhaseGuesses() throws {
        let rapidDuration = 162.011429
        let rapid = try #require(
            KnownAudioCatalog.shared.reviewedAnalysis(
                for: AudioFile(
                    filename: "00 Rapid Induction.mp3",
                    duration: rapidDuration,
                    fileSize: 1_024
                )
            )
        )
        let rapidPhases = try #require(rapid.hypnosisMetadata?.phases)
        let awakensDuration = 591.046531
        let awakens = try #require(
            KnownAudioCatalog.shared.reviewedAnalysis(
                for: AudioFile(
                    filename: "10 Bambi Awakens.mp3",
                    duration: awakensDuration,
                    fileSize: 1_024
                )
            )
        )
        let awakensPhases = try #require(awakens.hypnosisMetadata?.phases)

        #expect(rapidPhases.map(\.phase) == [.induction, .deepening])
        #expect(abs(rapidPhases[0].endTime - rapidDuration * 0.8023) < 0.01)
        #expect(awakensPhases.map(\.phase) == [.deepening, .emergence])
        #expect(abs(awakensPhases[1].startTime - awakensDuration * 0.90) < 0.01)
    }

    @Test func userTranscriptStillWinsOverBundledTranscript() throws {
        var file = AudioFile(
            filename: "01 - Instant Bimbo Sleepdoll.mp3",
            duration: 300,
            fileSize: 1_024
        )
        file.transcription = "My corrected personal transcript."

        let transcription = try #require(
            AnalysisStateManager.reusableTranscriptionResult(for: file)
        )

        #expect(transcription.fullText == "My corrected personal transcript.")
        #expect(transcription.segments.count == 1)
    }

    @Test func timestampBuilderCreatesMonotonicSegments() throws {
        let transcript = """
        [0:05] First sentence.
        [0:10-0:15] Second sentence.
        0:20 Third sentence.
        """

        let result = try #require(
            TimestampedTranscriptBuilder().makeResult(
                transcript: transcript,
                duration: 30
            )
        )

        #expect(result.fullText == "First sentence. Second sentence. Third sentence.")
        #expect(result.segments.map(\.timestamp) == [5, 10, 20])
        #expect(result.segments.map(\.duration) == [5, 10, 10])
    }

    @Test func timestampBuilderPreservesOpeningTextBeforeFirstMarker() throws {
        let transcript = """
        Opening words that must not be discarded.
        [1:00] Timed words.
        [2:00] Final words.
        """

        let result = try #require(
            TimestampedTranscriptBuilder().makeResult(
                transcript: transcript,
                duration: 180
            )
        )

        #expect(result.fullText.hasPrefix("Opening words that must not be discarded."))
        #expect(result.segments.first?.text == "Opening words that must not be discarded.")
        #expect(result.segments.first?.timestamp == 0)
    }
}
