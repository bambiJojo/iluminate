import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct CLIOptionsTests {

    @Test("Defaults: dry-run off, ambiguity low, count 1, out Corpus/synthetic")
    func defaults() throws {
        let o = try CLIOptions(arguments: [])
        #expect(o.dryRun == false)
        #expect(o.ambiguity == .low)
        #expect(o.count == 1)
        #expect(o.outDirectory.lastPathComponent == "synthetic")
        #expect(o.model == CLIOptions.defaultModel)
    }

    @Test("Parses flags")
    func parsesFlags() throws {
        let o = try CLIOptions(arguments: [
            "--dry-run", "--ambiguity", "high", "--count", "3",
            "--out", "/tmp/out", "--seeds", "/tmp/seeds", "--model", "claude-x",
        ])
        #expect(o.dryRun)
        #expect(o.ambiguity == .high)
        #expect(o.count == 3)
        #expect(o.outDirectory.path == "/tmp/out")
        #expect(o.seedsDirectory?.path == "/tmp/seeds")
        #expect(o.model == "claude-x")
    }

    @Test("Unknown ambiguity throws")
    func badAmbiguity() {
        #expect(throws: CLIOptionsError.self) {
            _ = try CLIOptions(arguments: ["--ambiguity", "banana"])
        }
    }

    @Test("--help sets showHelp")
    func help() throws {
        let o = try CLIOptions(arguments: ["--help"])
        #expect(o.showHelp)
    }

    @Test("--import-real sets import mode; --from overrides the source dir")
    func importReal() throws {
        let o = try CLIOptions(arguments: ["--import-real", "--from", "/tmp/tc"])
        #expect(o.importReal)
        #expect(o.fromDirectory.path == "/tmp/tc")
        #expect(o.outExplicit == false)   // out left at default so main picks Corpus/real
    }

    @Test("Default --from is ~/Documents/TrainingCorpus; --out sets outExplicit")
    func importDefaults() throws {
        let o = try CLIOptions(arguments: ["--import-real", "--out", "/tmp/real"])
        #expect(o.fromDirectory.lastPathComponent == "TrainingCorpus")
        #expect(o.outExplicit)
        #expect(o.outDirectory.path == "/tmp/real")
    }
}
