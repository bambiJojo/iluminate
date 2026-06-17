//  CLIOptions.swift
//  CorpusGenKit
//
//  Parses corpus-gen arguments. Pure value type so it is unit-testable.
//
import Foundation
import CorpusKit

public enum CLIOptionsError: Error, CustomStringConvertible {
    case missingValue(flag: String)
    case unknownAmbiguity(String)
    case unknownArchetype(String)
    case badCount(String)
    case badSeed(String)
    public var description: String {
        switch self {
        case .missingValue(let f): return "Missing value for \(f)"
        case .unknownAmbiguity(let v): return "Unknown --ambiguity '\(v)' (use low|medium|high)"
        case .unknownArchetype(let v):
            let valid = PhasePlan.Archetype.allCases.map(\.rawValue).joined(separator: "|")
            return "Unknown --archetypes '\(v)' (use \(valid)|all)"
        case .badCount(let v): return "Invalid --count '\(v)'"
        case .badSeed(let v): return "Invalid --seed '\(v)'"
        }
    }
}

public struct CLIOptions: Sendable {
    public static let defaultModel = "claude-sonnet-4-5"

    public var dryRun = false
    public var showHelp = false
    public var report = false
    public var ambiguity: CorpusAmbiguityLevel = .low
    public var archetypes: [PhasePlan.Archetype] = [.classic]
    public var count = 1
    public var seed: UInt64?
    public var outDirectory: URL
    public var outExplicit = false
    public var seedsDirectory: URL?
    public var model = CLIOptions.defaultModel

    /// When set, import LumeLabel labels into the corpus instead of generating.
    public var importReal = false
    /// When set, clean raw script books into ScriptCorpus instead of generating.
    public var importScripts = false
    /// Source TrainingCorpus directory for `--import-real`
    /// or raw scripts directory for `--import-scripts`
    /// (default ~/Documents/TrainingCorpus).
    public var fromDirectory: URL = .documentsDirectory.appending(path: "TrainingCorpus")

    public init(arguments: [String]) throws {
        // Default out = <repo>/Corpus/synthetic
        outDirectory = CorpusLoader.corpusRoot.appending(path: "synthetic")

        var i = 0
        func value(_ flag: String) throws -> String {
            guard i + 1 < arguments.count else { throw CLIOptionsError.missingValue(flag: flag) }
            i += 1
            return arguments[i]
        }
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "--dry-run": dryRun = true
            case "--report": report = true
            case "--help", "-h": showHelp = true
            case "--ambiguity":
                let v = try value(arg)
                guard let a = CorpusAmbiguityLevel(rawValue: v), a != .unspecified else {
                    throw CLIOptionsError.unknownAmbiguity(v)
                }
                ambiguity = a
            case "--archetype", "--archetypes":
                archetypes = try Self.parseArchetypes(try value(arg))
            case "--count":
                let v = try value(arg)
                guard let n = Int(v), n > 0 else { throw CLIOptionsError.badCount(v) }
                count = n
            case "--seed":
                let v = try value(arg)
                guard let parsed = UInt64(v), parsed > 0 else { throw CLIOptionsError.badSeed(v) }
                seed = parsed
            case "--out":
                outDirectory = URL(filePath: try value(arg))
                outExplicit = true
            case "--seeds": seedsDirectory = URL(filePath: try value(arg))
            case "--model": model = try value(arg)
            case "--import-real": importReal = true
            case "--import-scripts": importScripts = true
            case "--from": fromDirectory = URL(filePath: try value(arg))
            default: break
            }
            i += 1
        }
    }

    private static func parseArchetypes(_ raw: String) throws -> [PhasePlan.Archetype] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "all" else { return PhasePlan.Archetype.allCases }

        let parts = trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { throw CLIOptionsError.unknownArchetype(raw) }

        return try parts.map { part in
            guard let archetype = PhasePlan.Archetype(rawValue: part) else {
                throw CLIOptionsError.unknownArchetype(part)
            }
            return archetype
        }
    }

    public static let helpText = """
    corpus-gen — synthetic hypnosis corpus generator (dev tool)

      --dry-run           Use the offline stub responder (no network/API key)
      --report            Print corpus coverage/readiness report, then exit
      --ambiguity LEVEL   low | medium | high   (default low)
      --archetypes LIST   Comma-separated archetypes, or all (default classic)
      --count N           Number of cases to generate (default 1)
      --seed N            Deterministic generation seed (default current time)
      --out DIR           Output directory (default <repo>/Corpus/synthetic,
                          or <repo>/Corpus/real with --import-real)
      --seeds DIR         LumeLabel TrainingCorpus dir for few-shot seeds (optional)
      --model NAME        Anthropic model id (default \(defaultModel))
      --import-real       Import LumeLabel labels into Corpus/real (no generation)
      --import-scripts    Clean raw script books into ScriptCorpus (no generation)
      --from DIR          Source TrainingCorpus for --import-real, or raw script
                          directory for --import-scripts
                          (default ~/Documents/TrainingCorpus)
      --help              Show this help

    Archetypes: \(PhasePlan.Archetype.allCases.map(\.rawValue).joined(separator: ", "))

    Real generation reads ANTHROPIC_API_KEY from the environment.
    """
}
