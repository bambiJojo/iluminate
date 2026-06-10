import Testing
import Foundation
@testable import CorpusGenKit
@testable import CorpusKit

/// Contract for importing LumeLabel's on-disk label output into the evaluation
/// corpus. The importer reads the labeled-file JSON LumeLabel writes (plus the
/// cached WhisperKit transcript) and emits a real `CorpusCase` for `Corpus/real/`.
struct RealCorpusImporterTests {

    private let importer = RealCorpusImporter()

    // A labeled file as LumeLabel writes it (subset of fields the importer needs).
    private let labeledJSON = """
    {
      "id": "4F5D2BA2-530A-4352-9A39-A5562EA815C1",
      "originalFilename": "BF.mp3",
      "audioDuration": 300.0,
      "audioSHA256": "abc123",
      "expectedContentType": "hypnosis",
      "labeledAt": "2026-06-02T06:16:20Z",
      "phases": [
        { "phase": "pre_talk",  "startTime": 0.0,   "endTime": 80.0 },
        { "phase": "induction", "startTime": 80.0,  "endTime": 200.0 },
        { "phase": "deepening", "startTime": 200.0, "endTime": 300.0 }
      ]
    }
    """

    private let transcriptJSON = """
    {
      "audioSHA256": "abc123",
      "schemaVersion": 1,
      "transcription": {
        "duration": 300.0,
        "fullText": "close your eyes ... going deeper",
        "locale": "en",
        "segments": [
          { "text": "close your eyes", "timestamp": 0.0,  "duration": 80.0,  "confidence": 0.9 },
          { "text": "let go now",      "timestamp": 80.0, "duration": 120.0, "confidence": -0.3 }
        ]
      }
    }
    """

    private func decodeLabeled() throws -> LabeledFileDTO {
        try JSONDecoder().decode(LabeledFileDTO.self, from: Data(labeledJSON.utf8))
    }
    private func decodeTranscript() throws -> TranscriptCacheDTO {
        try JSONDecoder().decode(TranscriptCacheDTO.self, from: Data(transcriptJSON.utf8))
    }

    @Test("Maps a labeled file + transcript into a real, exact-mode CorpusCase")
    func mapsCase() throws {
        let kase = try importer.makeCase(labeled: decodeLabeled(), transcript: decodeTranscript())

        #expect(kase.source == .real)
        #expect(kase.boundaryMode == .exact)            // contiguous full labelings
        #expect(kase.duration == 300.0)
        #expect(kase.expectedContentTypeRaw == "hypnosis")
        // truth spans, in time order
        #expect(kase.truth.count == 3)
        #expect(kase.truth.first?.phase == .preTalk)
        #expect(kase.truth.last?.phase == .deepening)
        #expect(kase.truth.last?.end == 300.0)
        // transcript -> segments (negative WhisperKit confidence preserved)
        #expect(kase.segments.count == 2)
        #expect(kase.segments.last?.confidence == -0.3)
    }

    @Test("Case id is a real- prefixed slug of the original filename")
    func slugId() throws {
        let kase = try importer.makeCase(labeled: decodeLabeled(), transcript: decodeTranscript())
        #expect(kase.id == "real-bf")
    }

    @Test("A missing transcript yields valid truth with no segments")
    func missingTranscript() throws {
        let kase = try importer.makeCase(labeled: decodeLabeled(), transcript: nil)
        #expect(kase.segments.isEmpty)
        #expect(kase.truth.count == 3)
    }

    @Test("An unknown phase rawValue is rejected, not silently dropped")
    func unknownPhaseThrows() throws {
        let bad = """
        { "id": "x", "originalFilename": "x.mp3", "audioDuration": 10.0,
          "audioSHA256": "s", "expectedContentType": "hypnosis", "labeledAt": "2026-06-02T06:16:20Z",
          "phases": [ { "phase": "not_a_phase", "startTime": 0.0, "endTime": 10.0 } ] }
        """
        let dto = try JSONDecoder().decode(LabeledFileDTO.self, from: Data(bad.utf8))
        #expect(throws: RealCorpusImporter.ImportError.self) {
            _ = try importer.makeCase(labeled: dto, transcript: nil)
        }
    }

    @Test("importAll writes decodable CorpusCase files that CorpusLoader can read back")
    func importAllRoundTrips() throws {
        // Arrange a temp TrainingCorpus layout.
        let root = URL.temporaryDirectory.appending(path: "rci-\(UUID().uuidString)", directoryHint: .isDirectory)
        let transcriptDir = root.appending(path: "AnalyzerDataset/cache/transcripts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
        try Data(labeledJSON.utf8).write(to: root.appending(path: "labeled.json"))
        try Data(transcriptJSON.utf8).write(to: transcriptDir.appending(path: "abc123.json"))
        let outDir = root.appending(path: "out", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        // Act
        let written = try importer.importAll(trainingCorpusDir: root, into: outDir)

        // Assert: one file written, and it decodes back to the same case.
        #expect(written.count == 1)
        let data = try Data(contentsOf: try #require(written.first))
        let reloaded = try JSONDecoder().decode(CorpusCase.self, from: data)
        #expect(reloaded.id == "real-bf")
        #expect(reloaded.source == .real)
        #expect(reloaded.segments.count == 2)
        #expect(reloaded.truth.count == 3)
    }
}
