//  main.swift
//  CorpusGenerator (corpus-gen)
//
//  Dev-time CLI: generates synthetic hypnosis corpus cases. Uses the offline
//  stub responder for --dry-run or when ANTHROPIC_API_KEY is unset; otherwise
//  calls the Anthropic API. Never ships in the app bundle.
//
import Foundation
import CorpusKit
import CorpusGenKit

func run() async -> Int32 {
    let options: CLIOptions
    do {
        options = try CLIOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    } catch {
        FileHandle.standardError.write(Data("\(error)\n\n\(CLIOptions.helpText)\n".utf8))
        return 2
    }
    if options.showHelp {
        print(CLIOptions.helpText)
        return 0
    }

    // Import mode: convert LumeLabel labels into Corpus/real (no generation).
    if options.importReal {
        let outDir = options.outExplicit
            ? options.outDirectory
            : CorpusLoader.corpusRoot.appending(path: "real")
        do {
            let written = try RealCorpusImporter().importAll(
                trainingCorpusDir: options.fromDirectory, into: outDir
            )
            if written.isEmpty {
                print("No labeled files found under \(options.fromDirectory.path).")
            }
            for url in written {
                print("Imported \(url.lastPathComponent)")
            }
            print("Imported \(written.count) real case(s) into \(outDir.path).")
            return 0
        } catch {
            FileHandle.standardError.write(Data("Import failed: \(error)\n".utf8))
            return 1
        }
    }

    // Seeds (optional). Default seed dir = ~/Documents/TrainingCorpus.
    let seedDir = options.seedsDirectory
        ?? URL.homeDirectory.appending(path: "Documents").appending(path: "TrainingCorpus")
    let seeds = (try? SeedLibrary.load(from: seedDir)) ?? []
    let seedSetID = seeds.isEmpty ? nil : "seeds-\(seeds.count)"
    if seeds.isEmpty {
        print("No few-shot seeds found at \(seedDir.path); generating zero-shot.")
    } else {
        print("Loaded \(seeds.count) phase seed(s) from \(seedDir.path).")
    }

    // Responder selection.
    let responder: BlockResponder
    let modelStamp: String?
    if options.dryRun {
        responder = StubResponder()
        modelStamp = nil
        print("Dry run: using offline stub responder.")
    } else if let claude = ClaudeResponder.fromEnvironment(model: options.model) {
        responder = SeededResponder(base: claude, seeds: seeds)
        modelStamp = options.model
        print("Using Anthropic model \(options.model).")
    } else {
        responder = StubResponder()
        modelStamp = nil
        print("ANTHROPIC_API_KEY not set: falling back to offline stub responder.")
    }

    let assembler = SessionAssembler(responder: responder)
    var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970))

    for _ in 0..<options.count {
        let plan = PhasePlan.classic(using: &rng)
        do {
            let kase = try await assembler.assemble(
                plan: plan, ambiguity: options.ambiguity,
                idPrefix: "synth", model: modelStamp, seedSetID: seedSetID
            )
            let url = try CorpusWriter.write(kase, to: options.outDirectory)
            print("Wrote \(url.path)  (\(kase.truth.count) phases, \(Int(kase.duration))s)")
        } catch {
            FileHandle.standardError.write(Data("Generation failed: \(error)\n".utf8))
            return 1
        }
    }
    return 0
}

exit(await run())
