//
//  CorpusManagerView.swift
//  Ilumionate
//
//  List of ground-truth labeled audio files with status badges.
//  Accessed from Settings → Analyzer Training.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct CorpusManagerView: View {

    @State private var corpusManager = TrainingCorpusManager.shared
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if corpusManager.labeledFiles.isEmpty {
                    emptyState
                } else {
                    fileList
                }
            }
            .navigationTitle("Training Corpus")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import", systemImage: "plus.circle.fill") {
                        showingImporter = true
                    }
                    .foregroundStyle(Color.roseGold)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .navigationDestination(for: LabeledFile.self) { file in
                PhaseLabelingView(file: file)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TranceSpacing.content) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(Color.roseGold)

            Text("No Training Files")
                .font(TranceTypography.greeting)
                .foregroundStyle(Color.textPrimary)

            Text("Import audio files to label with ground-truth phase data")
                .font(TranceTypography.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            Button("Import Audio", systemImage: "plus.circle.fill") {
                showingImporter = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.roseGold)
        }
        .padding(TranceSpacing.screen)
    }

    // MARK: - File List

    private var fileList: some View {
        List {
            ForEach(corpusManager.labeledFiles) { file in
                NavigationLink(value: file) {
                    HStack(spacing: TranceSpacing.list) {
                        statusBadge(file.status)

                        VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                            Text(file.audioFilename)
                                .font(TranceTypography.body)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)

                            HStack(spacing: TranceSpacing.inner) {
                                Text(Duration.seconds(file.audioDuration).formatted(.time(pattern: .minuteSecond)))
                                Text("·")
                                Text(file.phases.count.formatted() + " phases")
                                Text("·")
                                Text(file.expectedContentType.rawValue.capitalized)
                            }
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    let file = corpusManager.labeledFiles[index]
                    Task {
                        try? await corpusManager.delete(file)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Helpers

    private func statusBadge(_ status: LabeledFile.LabelStatus) -> some View {
        let (icon, color): (String, Color) = switch status {
        case .unlabeled: ("circle.dashed", .textLight)
        case .rough:     ("circle.lefthalf.filled", .warmAccent)
        case .refined:   ("checkmark.circle.fill", .roseGold)
        }
        return Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(color)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        Task {
            for url in urls {
                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    _ = try await corpusManager.importAudio(from: url)
                } catch {
                    print("Failed to import \(url.lastPathComponent): \(error)")
                }
            }
        }
    }
}
