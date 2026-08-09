//
//  HomeContinuationContentTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct HomeContinuationContentTests {

    // MARK: - Fixtures

    private func audioFile(_ filename: String = "track.m4a") -> AudioFile {
        AudioFile(filename: filename, duration: 300, fileSize: 1_024, createdDate: Date())
    }

    private func snapshot(
        contentID: String,
        kind: ResumablePlaybackKind
    ) -> PlaybackProgressSnapshot {
        PlaybackProgressSnapshot(
            contentID: contentID,
            kind: kind,
            title: "Somewhere In The Middle",
            progress: 0.4,
            duration: 600,
            updatedAt: .now
        )
    }

    private func session(title: String = "Hypnagogic Drift") -> LightSession {
        LightSession(
            session_name: title,
            duration_sec: 600,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)
            ]
        )
    }

    private func script(id: String, title: String) -> TranceScript {
        TranceScript(
            schemaVersion: TranceScriptLibrary.currentSchemaVersion,
            id: id,
            title: title,
            theme: .relaxation,
            supportedArcs: [.fullText],
            language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [
                TranceScriptSegment(
                    phase: .induction,
                    text: "Settle.",
                    pacing: SegmentPacing(baseWPM: 150),
                    arcs: nil,
                    triggersHandoff: nil
                )
            ]
        )
    }

    private func document(id: String, title: String) -> ReadingDocument {
        ReadingDocument(
            id: id,
            title: title,
            kind: .pdf,
            originalFilename: "\(title).pdf",
            importedAt: .now,
            wordCount: 1_200,
            characterCount: 6_000,
            contentHash: "hash",
            textFilename: "\(id).txt"
        )
    }

    private func resumeState(scriptId: String, wordIndex: Int = 120) -> ReaderResumeState {
        ReaderResumeState(
            scriptId: scriptId,
            wordIndex: wordIndex,
            settings: PersistedReaderSettings(
                arc: .fullText,
                speedMultiplier: 1,
                subliminalEnabled: false,
                subliminalSpeed: .medium,
                binauralEnabled: false,
                lightEnabled: false,
                beatFrequency: 10
            ),
            phase: .reading,
            scriptContentHash: "hash",
            savedAt: .now
        )
    }

    // MARK: - Listening

    @Test
    func listeningKeepsSnapshotsWhoseContentStillExists() {
        let file = audioFile()
        let built = session()
        let snapshots = [
            snapshot(contentID: file.id.uuidString, kind: .audio),
            snapshot(contentID: built.id.uuidString, kind: .session)
        ]

        let kept = HomeContinuationContent.listening(
            snapshots: snapshots,
            audioFiles: [file],
            sessions: [built]
        )

        #expect(kept.map(\.contentID) == snapshots.map(\.contentID))
    }

    @Test
    func listeningDropsSnapshotsWhoseContentIsGone() {
        let deletedFile = audioFile()
        let missingSession = session()

        let kept = HomeContinuationContent.listening(
            snapshots: [
                snapshot(contentID: deletedFile.id.uuidString, kind: .audio),
                snapshot(contentID: missingSession.id.uuidString, kind: .session)
            ],
            audioFiles: [],
            sessions: []
        )

        #expect(kept.isEmpty)
    }

    @Test
    func listeningDoesNotMatchAnAudioSnapshotAgainstASession() {
        // Ids are UUIDs from separate namespaces; a snapshot must be resolved
        // against its own kind or a deleted file could resurrect as a session.
        let built = session()

        let kept = HomeContinuationContent.listening(
            snapshots: [snapshot(contentID: built.id.uuidString, kind: .audio)],
            audioFiles: [],
            sessions: [built]
        )

        #expect(kept.isEmpty)
    }

    @Test
    func listeningPreservesStoreOrder() {
        let first = audioFile("first.m4a")
        let second = audioFile("second.m4a")
        let gone = audioFile("gone.m4a")

        let kept = HomeContinuationContent.listening(
            snapshots: [
                snapshot(contentID: first.id.uuidString, kind: .audio),
                snapshot(contentID: gone.id.uuidString, kind: .audio),
                snapshot(contentID: second.id.uuidString, kind: .audio)
            ],
            audioFiles: [first, second],
            sessions: []
        )

        #expect(kept.map(\.contentID) == [first.id.uuidString, second.id.uuidString])
    }

    // MARK: - Reading

    @Test
    func readingIsNilWithoutASavedPosition() {
        #expect(
            HomeContinuationContent.reading(
                state: nil,
                importedScripts: [],
                bundledScripts: [script(id: "a", title: "A")],
                documents: []
            ) == nil
        )
    }

    @Test
    func readingResolvesABundledScriptTitle() throws {
        let resolved = try #require(
            HomeContinuationContent.reading(
                state: resumeState(scriptId: "deep-rest", wordIndex: 42),
                importedScripts: [],
                bundledScripts: [script(id: "deep-rest", title: "Deep Rest")],
                documents: []
            )
        )

        #expect(resolved == LibraryReadingContinuation(title: "Deep Rest", wordIndex: 42))
    }

    @Test
    func readingPrefersAnImportedScriptOverABundledOneWithTheSameID() throws {
        let resolved = try #require(
            HomeContinuationContent.reading(
                state: resumeState(scriptId: "deep-rest"),
                importedScripts: [script(id: "deep-rest", title: "Deep Rest (edited)")],
                bundledScripts: [script(id: "deep-rest", title: "Deep Rest")],
                documents: []
            )
        )

        #expect(resolved.title == "Deep Rest (edited)")
    }

    @Test
    func readingFallsBackToAnImportedDocument() throws {
        let doc = document(id: "abc123", title: "Trance Handbook")

        let resolved = try #require(
            HomeContinuationContent.reading(
                state: resumeState(scriptId: doc.scriptID, wordIndex: 900),
                importedScripts: [],
                bundledScripts: [],
                documents: [doc]
            )
        )

        #expect(resolved == LibraryReadingContinuation(title: "Trance Handbook", wordIndex: 900))
    }

    @Test
    func readingIsNilWhenTheSavedSourceNoLongerExists() {
        // A deleted import must not leave a Continue row that opens nothing.
        #expect(
            HomeContinuationContent.reading(
                state: resumeState(scriptId: "deleted-import"),
                importedScripts: [],
                bundledScripts: [script(id: "other", title: "Other")],
                documents: [document(id: "xyz", title: "Other Doc")]
            ) == nil
        )
    }
}
