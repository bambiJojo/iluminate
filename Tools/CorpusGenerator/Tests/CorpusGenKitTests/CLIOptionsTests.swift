import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct CLIOptionsTests {

    @Test("Defaults: dry-run off, ambiguity low, count 1, out Corpus/synthetic")
    func defaults() throws {
        let o = try CLIOptions(arguments: [])
        #expect(o.dryRun == false)
        #expect(o.report == false)
        #expect(o.ambiguity == .low)
        #expect(o.archetypes == [.classic])
        #expect(o.count == 1)
        #expect(o.seed == nil)
        #expect(o.outDirectory.lastPathComponent == "synthetic")
        #expect(o.model == CLIOptions.defaultModel)
    }

    @Test("Parses flags")
    func parsesFlags() throws {
        let o = try CLIOptions(arguments: [
            "--dry-run", "--ambiguity", "high", "--count", "3", "--seed", "12345",
            "--out", "/tmp/out", "--seeds", "/tmp/seeds", "--model", "claude-x",
        ])
        #expect(o.dryRun)
        #expect(o.ambiguity == .high)
        #expect(o.count == 3)
        #expect(o.seed == 12345)
        #expect(o.outDirectory.path == "/tmp/out")
        #expect(o.seedsDirectory?.path == "/tmp/seeds")
        #expect(o.model == "claude-x")
    }

    @Test("--report sets report mode")
    func reportMode() throws {
        let o = try CLIOptions(arguments: ["--report"])
        #expect(o.report)
    }

    @Test("Parses comma-separated archetypes")
    func parsesArchetypes() throws {
        let o = try CLIOptions(arguments: [
            "--archetypes", "classic,confusion_therapy,suggestion_conditioning",
        ])
        #expect(o.archetypes == [.classic, .confusionTherapy, .suggestionConditioning])
    }

    @Test("--archetypes all expands to every generation archetype")
    func parsesAllArchetypes() throws {
        let o = try CLIOptions(arguments: ["--archetypes", "all"])
        #expect(o.archetypes == PhasePlan.Archetype.allCases)
    }

    @Test("Unknown archetype throws")
    func badArchetype() {
        #expect(throws: CLIOptionsError.self) {
            _ = try CLIOptions(arguments: ["--archetypes", "classic,banana"])
        }
    }

    @Test("Bad seed throws")
    func badSeed() {
        #expect(throws: CLIOptionsError.self) {
            _ = try CLIOptions(arguments: ["--seed", "0"])
        }
        #expect(throws: CLIOptionsError.self) {
            _ = try CLIOptions(arguments: ["--seed", "banana"])
        }
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

    @Test("--import-scripts sets script import mode; --from points at raw scripts")
    func importScripts() throws {
        let o = try CLIOptions(arguments: ["--import-scripts", "--from", "/tmp/raw-scripts", "--out", "/tmp/scripts"])
        #expect(o.importScripts)
        #expect(o.fromDirectory.path == "/tmp/raw-scripts")
        #expect(o.outDirectory.path == "/tmp/scripts")
        #expect(o.outExplicit)
    }
}
