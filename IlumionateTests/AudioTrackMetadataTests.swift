//
//  AudioTrackMetadataTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct AudioTrackMetadataTests {
    @Test func extractsAnnouncedCreatorAndTitleFromIntroduction() {
        let metadata = AudioIntroductionMetadataExtractor.metadata(
            from: "Hello, this is Michael Sealy, and this is Deep Sleep Hypnosis. Make yourself comfortable.",
            filename: "Deep Sleep Hypnosis.mp3"
        )

        #expect(metadata?.creator == "Michael Sealy")
        #expect(metadata?.generatedTitle == "Deep Sleep Hypnosis")
        #expect(metadata?.confidence == 0.96)
    }

    @Test func extractsSentenceSeparatedIntroduction() {
        let metadata = AudioIntroductionMetadataExtractor.metadata(
            from: "Hi, I'm Sarah Williams. Welcome to Calm Confidence. Take a slow breath.",
            filename: "track-01.m4a"
        )

        #expect(metadata?.creator == "Sarah Williams")
        #expect(metadata?.generatedTitle == "Calm Confidence")
    }

    @Test func doesNotTreatSessionDescriptionAsCreator() {
        let metadata = AudioIntroductionMetadataExtractor.metadata(
            from: "This is a relaxing hypnosis session for sleep. Close your eyes.",
            filename: "sleep.m4a"
        )

        #expect(metadata?.creator == nil)
    }

    @Test func fuzzyMatchCorrectsMinorTranscriptionDifferences() {
        let match = AudioIntroductionMetadataExtractor.closestMatch(
            to: "Michael Sealy",
            among: ["Sarah Williams", "Michael Sealey", "Unknown Creator"]
        )

        #expect(match == "Michael Sealey")
        #expect(
            AudioIntroductionMetadataExtractor.closestMatch(
                to: "Completely Different",
                among: ["Michael Sealey"]
            ) == nil
        )
    }

    @Test func catalogMatchConfirmsCloseSpokenCreatorAndTitle() {
        let expected = AudioCatalogMetadataVerifier.Candidate(
            title: "Deep Sleep Hypnosis: Fall Asleep Fast",
            creator: "Michael Sealey",
            album: "Guided Sleep Hypnosis",
            genre: "Self-Development",
            duration: 2_100,
            url: URL(string: "https://example.com/track")
        )

        let match = AudioCatalogMetadataVerifier.bestMatch(
            title: "Deep Sleep Hypnosis",
            creator: "Michael Sealy",
            duration: 2_080,
            candidates: [expected]
        )

        #expect(match == expected)
    }

    @Test func catalogMatchRejectsWrongCreatorOrGenericTitle() {
        let candidates = [
            AudioCatalogMetadataVerifier.Candidate(
                title: "Deep Sleep Hypnosis",
                creator: "Someone Else",
                album: nil,
                genre: nil,
                duration: 2_100,
                url: nil
            ),
            AudioCatalogMetadataVerifier.Candidate(
                title: "Sleep",
                creator: "Michael Sealey",
                album: nil,
                genre: nil,
                duration: 2_100,
                url: nil
            )
        ]

        let match = AudioCatalogMetadataVerifier.bestMatch(
            title: "Deep Sleep Hypnosis",
            creator: "Michael Sealy",
            duration: 2_080,
            candidates: candidates
        )

        #expect(match == nil)
    }

    @Test func verifiedMetadataReplacesInferenceAndRecordsProvenance() {
        let inferred = AudioTrackMetadata(
            generatedTitle: "Deep Sleap Hypnosis",
            creator: "Michael Sealy",
            themes: ["Sleep"],
            confidence: 0.88
        )
        let verified = AudioTrackMetadata(
            generatedTitle: "Deep Sleep Hypnosis",
            creator: "Michael Sealey",
            album: "Guided Sleep Hypnosis",
            genre: "Self-Development",
            confidence: 0.97,
            verificationSource: "Apple catalog",
            verificationURL: URL(string: "https://example.com/track")
        )

        let merged = inferred.mergingVerified(verified)

        #expect(merged.generatedTitle == "Deep Sleep Hypnosis")
        #expect(merged.creator == "Michael Sealey")
        #expect(merged.themes == ["Sleep"])
        #expect(merged.verificationSource == "Apple catalog")
    }

    @Test func displayTitleUsesUserThenEmbeddedThenGeneratedThenFilename() {
        var file = AudioFile(
            filename: "original-name.m4a",
            duration: 120,
            fileSize: 100,
            trackMetadata: AudioTrackMetadata(
                embeddedTitle: "Embedded Title",
                generatedTitle: "Generated Title"
            )
        )

        #expect(file.displayName == "Embedded Title")
        file.trackMetadata?.embeddedTitle = nil
        #expect(file.displayName == "Generated Title")
        file.userTitle = "My Title"
        #expect(file.displayName == "My Title")
        file.userTitle = nil
        file.trackMetadata = nil
        #expect(file.displayName == "original-name")
    }

    @Test func metadataMergePreservesEmbeddedTagsAndAddsAnalysis() {
        let embedded = AudioTrackMetadata(
            embeddedTitle: "Tagged Title",
            creator: "Tagged Creator",
            album: "Tagged Album"
        )
        let analyzed = AudioTrackMetadata(
            generatedTitle: "Generated Title",
            creator: "Guessed Creator",
            themes: ["Relaxation", "Sleep", "relaxation"],
            confidence: 0.82
        )

        let merged = embedded.mergingAnalyzed(analyzed)

        #expect(merged.preferredTitle == "Tagged Title")
        #expect(merged.generatedTitle == "Generated Title")
        #expect(merged.creator == "Tagged Creator")
        #expect(merged.album == "Tagged Album")
        #expect(merged.themes == ["Relaxation", "Sleep"])
        #expect(merged.confidence == 0.82)
    }

    @Test @MainActor func cacheSurvivesDeleteAndReimportWithDifferentFilename() throws {
        let cacheURL = URL.temporaryDirectory
            .appending(path: "AnalysisCache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let fingerprint = String(repeating: "b", count: 64)
        let analyzedMetadata = AudioTrackMetadata(
            generatedTitle: "Deep Confidence Reset",
            creator: "A. Narrator",
            themes: ["Confidence", "Relaxation"],
            confidence: 0.9
        )
        let analysis = AnalysisResult(
            mood: .relaxing,
            energyLevel: 0.2,
            suggestedFrequencyRange: 4...8,
            suggestedIntensity: 0.5,
            keyMoments: [],
            aiSummary: "A confidence-focused relaxation session.",
            recommendedPreset: "Deep Theta",
            contentType: .hypnosis,
            discoveredMetadata: analyzedMetadata
        )
        let original = AudioFile(
            filename: "first-name.m4a",
            duration: 300,
            fileSize: 10_000,
            contentFingerprint: fingerprint
        )
        let completion = CompletedAnalysis(
            audioFile: original,
            transcription: AnalysisFixtures.basicTranscription,
            analysis: analysis,
            completedAt: .now
        )

        let writer = AnalysisStateManager(
            transcriber: MockAudioTranscriber(),
            analyzer: MockContentAnalyzer(),
            cacheURL: cacheURL
        )
        writer.cache(completion, for: original)

        let reader = AnalysisStateManager(
            transcriber: MockAudioTranscriber(),
            analyzer: MockContentAnalyzer(),
            cacheURL: cacheURL
        )
        let reimported = AudioFile(
            filename: "renamed-copy.m4a",
            duration: 300,
            fileSize: 10_000,
            trackMetadata: AudioTrackMetadata(embeddedTitle: "Fresh Embedded Title"),
            contentFingerprint: fingerprint
        )
        let restored = reader.restoringCachedData(in: reimported)

        #expect(restored.isAnalyzed)
        #expect(restored.transcription == AnalysisFixtures.basicTranscription.fullText)
        #expect(restored.displayName == "Fresh Embedded Title")
        #expect(restored.creatorDisplayName == "A. Narrator")
        #expect(restored.discoveredThemes == ["Confidence", "Relaxation"])
    }
}
