//
//  KnownAudioCatalogFixtures.swift
//  IlumionateTests
//

import Foundation
@testable import Ilumionate

nonisolated enum KnownAudioCatalogFixtures {
    static let recognizedFilename = "01 - Example Reviewed Session.mp3"
    static let title = "Example Reviewed Session"
    static let transcript = """
    [00:00] Settle comfortably and notice your breathing.
    [01:00] Continue relaxing while the session gently deepens.
    """
    static let expectedTranscript = "Settle comfortably and notice your breathing. Continue relaxing while the session gently deepens."

    static let bundledTranscriptCatalog = BundledAudioTranscriptCatalog(
        entries: [
            .init(
                title: title,
                aliases: [recognizedFilename],
                transcript: transcript
            )
        ]
    )

    static let knownAudioCatalog = KnownAudioCatalog(
        entries: [
            KnownAudioCatalogEntry(
                id: "unit-test-reviewed-session",
                series: "Synthetic Test Sessions",
                trackNumber: "01",
                title: title,
                aliases: [recognizedFilename],
                contentFingerprints: [],
                role: .suggestions,
                seedProfile: .conditioning,
                creator: "Test Fixture",
                sourceKind: .localAudioReview,
                sourceDocument: "Synthetic unit-test fixture",
                sourceURL: nil,
                transcript: transcript,
                goldLightScore: KnownAudioGoldLightScore(
                    scoreVersion: 1,
                    sessionID: UUID(),
                    designIntent: "Exercise the reviewed-catalog path in tests.",
                    playlistPlacement: .middle,
                    evidenceKind: .localAudioReview,
                    timingBasis: .reviewedAudioTiming,
                    referenceDuration: 120,
                    transcriptCoverage: 1,
                    transcriptAnchorCount: 1,
                    evidenceAnchors: [
                        KnownAudioGoldEvidenceAnchor(
                            position: 0.5,
                            cue: "Synthetic reviewed transition",
                            source: .reviewedIntent
                        )
                    ],
                    moments: [
                        KnownAudioGoldLightMoment(
                            position: 0,
                            frequency: 4,
                            intensity: 0.4,
                            waveform: .sine,
                            rampDuration: nil,
                            bilateral: false,
                            bilateralTransitionDuration: nil,
                            colorTemperature: 2_800
                        ),
                        KnownAudioGoldLightMoment(
                            position: 0.5,
                            frequency: 6,
                            intensity: 0.6,
                            waveform: .softPulse,
                            rampDuration: 2,
                            bilateral: true,
                            bilateralTransitionDuration: 1,
                            colorTemperature: 3_000
                        ),
                        KnownAudioGoldLightMoment(
                            position: 1,
                            frequency: 4,
                            intensity: 0.4,
                            waveform: .sine,
                            rampDuration: 2,
                            bilateral: false,
                            bilateralTransitionDuration: 1,
                            colorTemperature: 2_800
                        )
                    ]
                )
            )
        ]
    )
}
