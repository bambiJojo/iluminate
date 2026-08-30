//
//  LumeLabelApp.swift
//  LumeLabel
//
//  macOS utility for labeling hypnosis audio files with ground-truth
//  phase annotations. Labels are written to ~/Documents/TrainingCorpus/
//  — the same location read by the evolutionary optimizer test suite.
//

import AppKit
import SwiftUI

@MainActor
final class LumeLabelAppDelegate: NSObject, NSApplicationDelegate {
    private var unattendedCorpus: TrainingCorpusManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.arguments.contains("--derive-bambi-silver") else { return }

        let corpus = TrainingCorpusManager.shared
        unattendedCorpus = corpus
        Task {
            while corpus.hasFinishedInitialLoad == false {
                try? await Task.sleep(for: .milliseconds(100))
            }
            BambiDerivedLabelingController.shared.start(corpus: corpus)
        }
    }
}

@main
struct LumeLabelApp: App {

    @NSApplicationDelegateAdaptor(LumeLabelAppDelegate.self) private var appDelegate
    @State private var corpus = TrainingCorpusManager.shared
    @State private var labelingSprint = LabelingSprintController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(corpus)
                .environment(labelingSprint)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
