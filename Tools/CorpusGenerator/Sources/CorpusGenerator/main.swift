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

    if options.report {
        do {
            let cases = try ["fixtures", "synthetic", "real"].flatMap { subdirectory in
                try CorpusLoader.load(subdirectory: subdirectory)
            }
            print(CorpusReport.make(cases: cases).text)
            return 0
        } catch {
            FileHandle.standardError.write(Data("Report failed: \(error)\n".utf8))
            return 1
        }
    }

    // Script import mode: convert raw RTF/text script books into clean ScriptCorpus text files.
    if options.importScripts {
        let outDir = options.outExplicit
            ? options.outDirectory
            : CorpusLoader.corpusRoot.deletingLastPathComponent().appending(path: "ScriptCorpus")
        do {
            let report = ScriptCorpusExtractor.extract(from: options.fromDirectory, fileManager: .default)
            let written = try ScriptCorpusExtractor.writeScriptCorpus(report, to: outDir)

            let reviewCount = report.blocks.filter { $0.qualityFlags.contains(ScriptCorpusExtractionFlag.needsReview) }.count
            print("Extracted \(report.blocks.count) script block(s) from \(options.fromDirectory.path).")
            print("Wrote \(written.count) file(s) into \(outDir.path).")
            if reviewCount > 0 {
                print("\(reviewCount) block(s) were flagged for review; inspect _extraction_manifest.json.")
            }
            if report.issues.isEmpty == false {
                print("\(report.issues.count) issue(s) were recorded; inspect _extraction_manifest.json.")
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Script import failed: \(error)\n".utf8))
            return 1
        }
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
    let generationSeed = options.seed ?? UInt64(Date().timeIntervalSince1970)
    var rng = SeededRNG(seed: generationSeed)
    print("Generation seed \(generationSeed).")

    for index in 0..<options.count {
        let archetype = options.archetypes[index % options.archetypes.count]
        let plan = PhasePlan.make(archetype: archetype, using: &rng)
        let caseID = options.seed.map { "synth-\(plan.archetype)-seed\($0)-\(String(format: "%04d", index + 1))" }
        do {
            let kase = try await assembler.assemble(
                plan: plan, ambiguity: options.ambiguity,
                idPrefix: "synth", model: modelStamp, seedSetID: seedSetID,
                caseID: caseID, generationSeed: options.seed
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
