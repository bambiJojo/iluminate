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
    case badCount(String)
    public var description: String {
        switch self {
        case .missingValue(let f): return "Missing value for \(f)"
        case .unknownAmbiguity(let v): return "Unknown --ambiguity '\(v)' (use low|medium|high)"
        case .badCount(let v): return "Invalid --count '\(v)'"
        }
    }
}

public struct CLIOptions: Sendable {
    public static let defaultModel = "claude-sonnet-4-5"

    public var dryRun = false
    public var showHelp = false
    public var ambiguity: CorpusAmbiguityLevel = .low
    public var count = 1
    public var outDirectory: URL
    public var seedsDirectory: URL?
    public var model = CLIOptions.defaultModel

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
            case "--help", "-h": showHelp = true
            case "--ambiguity":
                let v = try value(arg)
                guard let a = CorpusAmbiguityLevel(rawValue: v), a != .unspecified else {
                    throw CLIOptionsError.unknownAmbiguity(v)
                }
                ambiguity = a
            case "--count":
                let v = try value(arg)
                guard let n = Int(v), n > 0 else { throw CLIOptionsError.badCount(v) }
                count = n
            case "--out": outDirectory = URL(filePath: try value(arg))
            case "--seeds": seedsDirectory = URL(filePath: try value(arg))
            case "--model": model = try value(arg)
            default: break
            }
            i += 1
        }
    }

    public static let helpText = """
    corpus-gen — synthetic hypnosis corpus generator (dev tool)

      --dry-run           Use the offline stub responder (no network/API key)
      --ambiguity LEVEL   low | medium | high   (default low)
      --count N           Number of cases to generate (default 1)
      --out DIR           Output directory (default <repo>/Corpus/synthetic)
      --seeds DIR         LumeLabel TrainingCorpus dir for few-shot seeds (optional)
      --model NAME        Anthropic model id (default \(defaultModel))
      --help              Show this help

    Real generation reads ANTHROPIC_API_KEY from the environment.
    """
}
