//
//  main.swift
//  AnalyzerImprover
//
//  Developer-facing command-line utility for measuring and improving
//  analyzer performance against exported training data.
//

import Foundation
import Darwin

enum AnalyzerImproverCLI {
    static func run() async {
        do {
            let options = try CLIOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.shouldShowHelp {
                print(CLIOptions.helpText)
                exit(EXIT_SUCCESS)
            }

            let seedConfig = try options.loadSeedConfig()
            let optimizer = AnalyzerOptimizer(
                corpusDirectory: options.corpusDirectory,
                outputDirectory: options.outputDirectory
            )

            switch options.command {
            case .measure:
                let result = try await optimizer.measure(
                    config: seedConfig,
                    evaluationMode: options.evaluationMode
                )
                print("Measured analyzer match against \(result.scorecard.evaluatedExampleCount) examples.")
                print("Match percentage: \(formatPercent(result.scorecard.matchPercentage))")
                print("Overall score: \(formatScore(result.scorecard.overallMetrics.overallScore))")
                print("Scorecard: \(result.outputURL.path())")
                print("History: \(result.historyURL.path())")

            case .optimize:
                let result = try await optimizer.run(
                    seedConfig: seedConfig,
                    params: options.makeOptimizerParameters(),
                    onProgress: { progress in
                        if let generation = progress.generation {
                            print("[generation \(generation)] \(progress.message)")
                        } else {
                            print(progress.message)
                        }
                    }
                )

                print("Optimization complete.")
                print("Best generation: \(result.report.selectedConfigGeneration)")
                print("Best validation score: \(formatScore(result.report.bestValidationMetrics.overallScore))")
                print("Overall match percentage: \(formatPercent(result.scorecard.matchPercentage))")
                print("Config: \(result.outputFiles.configURL.path())")
                print("Report: \(result.outputFiles.reportURL.path())")
                print("Diagnostics: \(result.outputFiles.diagnosticsURL.path())")
                print("History: \(result.outputFiles.historyURL.path())")
                print("Scorecard: \(result.outputFiles.scorecardURL.path())")
                print("Match history: \(result.outputFiles.scorecardHistoryURL.path())")
            }

            exit(EXIT_SUCCESS)
        } catch let error as CLIError {
            fputs("AnalyzerImprover error: \(error.localizedDescription)\n", stderr)
            fputs("\n\(CLIOptions.helpText)\n", stderr)
            exit(EXIT_FAILURE)
        } catch {
            fputs("AnalyzerImprover failed: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func formatPercent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(2)))
    }

    private static func formatScore(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(4)))
    }
}

await AnalyzerImproverCLI.run()

private enum CLICommand: String {
    case measure
    case optimize
}

private enum CLIError: LocalizedError {
    case missingCommand
    case unknownCommand(String)
    case missingValue(String)
    case invalidMode(String)
    case invalidInteger(flag: String, value: String)
    case invalidDouble(flag: String, value: String)
    case unreadableConfig(URL, String)

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            return "No command was provided."
        case .unknownCommand(let command):
            return "Unknown command '\(command)'."
        case .missingValue(let flag):
            return "Expected a value after \(flag)."
        case .invalidMode(let value):
            return "Unknown evaluation mode '\(value)'. Use keywordOnly, chunkedOnly, or hybridRuntime."
        case .invalidInteger(let flag, let value):
            return "Expected an integer for \(flag), but received '\(value)'."
        case .invalidDouble(let flag, let value):
            return "Expected a number for \(flag), but received '\(value)'."
        case .unreadableConfig(let url, let reason):
            return "Could not load config at \(url.path()): \(reason)"
        }
    }
}

private struct CLIOptions {
    let command: CLICommand
    let shouldShowHelp: Bool
    let corpusDirectory: URL
    let outputDirectory: URL
    let evaluationMode: AnalyzerEvaluationMode
    let explicitConfigURL: URL?
    let publishBestConfig: Bool
    let populationSize: Int
    let maxGenerations: Int
    let elitismCount: Int
    let mutationRate: Double
    let earlyStopPatience: Int
    let trainFraction: Double
    let validationFraction: Double

    private init(
        command: CLICommand,
        shouldShowHelp: Bool,
        corpusDirectory: URL,
        outputDirectory: URL,
        evaluationMode: AnalyzerEvaluationMode,
        explicitConfigURL: URL?,
        publishBestConfig: Bool,
        populationSize: Int,
        maxGenerations: Int,
        elitismCount: Int,
        mutationRate: Double,
        earlyStopPatience: Int,
        trainFraction: Double,
        validationFraction: Double
    ) {
        self.command = command
        self.shouldShowHelp = shouldShowHelp
        self.corpusDirectory = corpusDirectory
        self.outputDirectory = outputDirectory
        self.evaluationMode = evaluationMode
        self.explicitConfigURL = explicitConfigURL
        self.publishBestConfig = publishBestConfig
        self.populationSize = populationSize
        self.maxGenerations = maxGenerations
        self.elitismCount = elitismCount
        self.mutationRate = mutationRate
        self.earlyStopPatience = earlyStopPatience
        self.trainFraction = trainFraction
        self.validationFraction = validationFraction
    }

    init(arguments: [String]) throws {
        guard let first = arguments.first else {
            throw CLIError.missingCommand
        }

        if first == "--help" || first == "-h" || first == "help" {
            self = CLIOptions(
                command: .measure,
                shouldShowHelp: true,
                corpusDirectory: URL.documentsDirectory.appending(path: "TrainingCorpus"),
                outputDirectory: URL.documentsDirectory.appending(path: "TrainingOutput"),
                evaluationMode: .keywordOnly,
                explicitConfigURL: nil,
                publishBestConfig: false,
                populationSize: 8,
                maxGenerations: 8,
                elitismCount: 2,
                mutationRate: 0.85,
                earlyStopPatience: 4,
                trainFraction: 0.7,
                validationFraction: 0.15
            )
            return
        }

        guard let command = CLICommand(rawValue: first) else {
            throw CLIError.unknownCommand(first)
        }

        var corpusDirectory = URL.documentsDirectory.appending(path: "TrainingCorpus")
        var outputDirectory = URL.documentsDirectory.appending(path: "TrainingOutput")
        var evaluationMode: AnalyzerEvaluationMode = .keywordOnly
        var explicitConfigURL: URL?
        var publishBestConfig = false
        var populationSize = 8
        var maxGenerations = 8
        var elitismCount = 2
        var mutationRate = 0.85
        var earlyStopPatience = 4
        var trainFraction = 0.7
        var validationFraction = 0.15

        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--help", "-h":
                self = CLIOptions(
                    command: command,
                    shouldShowHelp: true,
                    corpusDirectory: corpusDirectory,
                    outputDirectory: outputDirectory,
                    evaluationMode: evaluationMode,
                    explicitConfigURL: explicitConfigURL,
                    publishBestConfig: publishBestConfig,
                    populationSize: populationSize,
                    maxGenerations: maxGenerations,
                    elitismCount: elitismCount,
                    mutationRate: mutationRate,
                    earlyStopPatience: earlyStopPatience,
                    trainFraction: trainFraction,
                    validationFraction: validationFraction
                )
                return
            case "--corpus":
                index += 1
                corpusDirectory = try Self.urlValue(for: flag, at: index, in: arguments)
            case "--output":
                index += 1
                outputDirectory = try Self.urlValue(for: flag, at: index, in: arguments)
            case "--config":
                index += 1
                explicitConfigURL = try Self.urlValue(for: flag, at: index, in: arguments)
            case "--mode":
                index += 1
                let rawMode = try Self.stringValue(for: flag, at: index, in: arguments)
                guard let parsedMode = AnalyzerEvaluationMode(rawValue: rawMode) else {
                    throw CLIError.invalidMode(rawMode)
                }
                evaluationMode = parsedMode
            case "--population":
                index += 1
                populationSize = try Self.intValue(for: flag, at: index, in: arguments)
            case "--generations":
                index += 1
                maxGenerations = try Self.intValue(for: flag, at: index, in: arguments)
            case "--elitism":
                index += 1
                elitismCount = try Self.intValue(for: flag, at: index, in: arguments)
            case "--mutation-rate":
                index += 1
                mutationRate = try Self.doubleValue(for: flag, at: index, in: arguments)
            case "--patience":
                index += 1
                earlyStopPatience = try Self.intValue(for: flag, at: index, in: arguments)
            case "--train-fraction":
                index += 1
                trainFraction = try Self.doubleValue(for: flag, at: index, in: arguments)
            case "--validation-fraction":
                index += 1
                validationFraction = try Self.doubleValue(for: flag, at: index, in: arguments)
            case "--publish":
                publishBestConfig = true
            default:
                throw CLIError.unknownCommand(flag)
            }
            index += 1
        }

        self.command = command
        self.shouldShowHelp = false
        self.corpusDirectory = corpusDirectory
        self.outputDirectory = outputDirectory
        self.evaluationMode = evaluationMode
        self.explicitConfigURL = explicitConfigURL
        self.publishBestConfig = publishBestConfig
        self.populationSize = populationSize
        self.maxGenerations = maxGenerations
        self.elitismCount = elitismCount
        self.mutationRate = mutationRate
        self.earlyStopPatience = earlyStopPatience
        self.trainFraction = trainFraction
        self.validationFraction = validationFraction
    }

    func loadSeedConfig() throws -> AnalyzerConfig {
        let decoder = JSONDecoder()

        if let explicitConfigURL {
            do {
                let data = try Data(contentsOf: explicitConfigURL)
                return try decoder.decode(AnalyzerConfig.self, from: data)
            } catch {
                throw CLIError.unreadableConfig(explicitConfigURL, error.localizedDescription)
            }
        }

        for candidate in Self.defaultConfigCandidates {
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            do {
                let data = try Data(contentsOf: candidate)
                return try decoder.decode(AnalyzerConfig.self, from: data)
            } catch {
                throw CLIError.unreadableConfig(candidate, error.localizedDescription)
            }
        }

        return AnalyzerConfigLoader.load()
    }

    func makeOptimizerParameters() -> AnalyzerOptimizer.Parameters {
        AnalyzerOptimizer.Parameters(
            populationSize: populationSize,
            maxGenerations: maxGenerations,
            elitismCount: elitismCount,
            mutationRate: mutationRate,
            earlyStopPatience: earlyStopPatience,
            trainFraction: trainFraction,
            validationFraction: validationFraction,
            evaluationMode: evaluationMode,
            publishBestConfigToDocuments: publishBestConfig
        )
    }

    static let helpText = """
    Usage:
      AnalyzerImprover measure [options]
      AnalyzerImprover optimize [options]

    Commands:
      measure                  Evaluate analyzer output against the training dataset.
      optimize                 Run the optimizer loop and emit a stronger analyzer config.

    Options:
      --corpus <path>          Training corpus root. Default: ~/Documents/TrainingCorpus
      --output <path>          Output directory. Default: ~/Documents/TrainingOutput
      --config <path>          Optional seed config JSON to evaluate or mutate.
      --mode <mode>            keywordOnly | chunkedOnly | hybridRuntime
      --population <count>     Optimizer population size. Default: 8
      --generations <count>    Optimizer generation count. Default: 8
      --elitism <count>        Elite survivors per generation. Default: 2
      --mutation-rate <value>  Mutation rate from 0.0 to 1.0. Default: 0.85
      --patience <count>       Early-stop patience in generations. Default: 4
      --train-fraction <value> Train split fraction. Default: 0.7
      --validation-fraction <value>
                                Validation split fraction. Default: 0.15
      --publish                Save the best optimized config to ~/Documents/AnalyzerConfig.json
      Note: this utility currently relies on cached transcripts in AnalyzerDataset/cache/transcripts.
      --help                   Show this help message.
    """

    private static var defaultConfigCandidates: [URL] {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        return [
            AnalyzerConfigLoader.documentsConfigURL,
            currentDirectory.appending(path: "Ilumionate/AnalyzerConfig/AnalyzerConfig_default.json"),
            currentDirectory.appending(path: "AnalyzerConfig/AnalyzerConfig_default.json"),
            executableDirectory.appending(path: "AnalyzerConfig_default.json")
        ]
    }

    private static func stringValue(for flag: String, at index: Int, in arguments: [String]) throws -> String {
        guard arguments.indices.contains(index) else {
            throw CLIError.missingValue(flag)
        }
        return arguments[index]
    }

    private static func urlValue(for flag: String, at index: Int, in arguments: [String]) throws -> URL {
        URL(fileURLWithPath: try stringValue(for: flag, at: index, in: arguments)).standardizedFileURL
    }

    private static func intValue(for flag: String, at index: Int, in arguments: [String]) throws -> Int {
        let rawValue = try stringValue(for: flag, at: index, in: arguments)
        guard let value = Int(rawValue) else {
            throw CLIError.invalidInteger(flag: flag, value: rawValue)
        }
        return value
    }

    private static func doubleValue(for flag: String, at index: Int, in arguments: [String]) throws -> Double {
        let rawValue = try stringValue(for: flag, at: index, in: arguments)
        guard let value = Double(rawValue) else {
            throw CLIError.invalidDouble(flag: flag, value: rawValue)
        }
        return value
    }
}
