import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct SeedLibraryTests {

    private var fixturesDir: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()       // .../CorpusGenKitTests
            .appending(path: "Fixtures")
    }

    @Test("Loads per-phase excerpts by slicing the transcript at phase anchors")
    func loadsSeeds() throws {
        let seeds = try SeedLibrary.load(from: fixturesDir)
        // Two phases in the label → up to two seeds (segments fall in each window).
        #expect(seeds.contains { $0.phase == .induction })
        #expect(seeds.contains { $0.phase == .deepening })
        let induction = seeds.first { $0.phase == .induction }
        #expect(induction?.excerpt.localizedCaseInsensitiveContains("close your eyes") == true)
        let deepening = seeds.first { $0.phase == .deepening }
        #expect(deepening?.excerpt.localizedCaseInsensitiveContains("deeper") == true)
    }

    @Test("Missing directory yields no seeds (graceful zero-shot fallback)")
    func missingDirIsEmpty() throws {
        let seeds = try SeedLibrary.load(from: URL(filePath: "/definitely/not/here"))
        #expect(seeds.isEmpty)
    }
}
