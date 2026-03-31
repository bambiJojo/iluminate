//
//  CorpusSidebarView.swift
//  LumeLabel
//
//  Sidebar listing all labeled files with status badges and drag-drop import.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import CoreMedia

struct CorpusSidebarView: View {

    @Environment(TrainingCorpusManager.self) private var corpus
    @Binding var selectedFile: LabeledFile?
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        List(corpus.labeledFiles, selection: $selectedFile) { file in
            CorpusFileRow(file: file)
                .tag(file)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        if selectedFile?.id == file.id { selectedFile = nil }
                        corpus.delete(file)
                    }
                }
        }
        .navigationTitle("Corpus")
        .navigationSubtitle(subtitleText)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Import Audio", systemImage: "plus") {
                    isImporting = true
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { importURL(url) }
            return !urls.isEmpty
        }
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private var subtitleText: String {
        let total = corpus.labeledFiles.count
        let labeled = corpus.labeledFiles.filter { $0.status != .unlabeled }.count
        return "\(labeled)/\(total) labeled"
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            importURL(url)
        }
    }

    private func importURL(_ url: URL) {
        do {
            var file = try corpus.importAudio(from: url)
            Task {
                let asset = AVURLAsset(url: corpus.audioURL(for: file))
                if let duration = try? await asset.load(.duration) {
                    file.audioDuration = CMTimeGetSeconds(duration)
                    try? corpus.save(file)
                }
            }
        } catch {
            importError = error.localizedDescription
        }
    }
}

// MARK: - File Row

struct CorpusFileRow: View {

    let file: LabeledFile

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(file.audioFilename)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(Duration.seconds(file.audioDuration).formatted(.time(pattern: .minuteSecond)))
                    Text("·")
                    Text("\(file.phases.count) phase\(file.phases.count == 1 ? "" : "s")")
                    Text("·")
                    Text(file.expectedContentType.rawValue.capitalized)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: some View {
        let (icon, color): (String, Color) = switch file.status {
        case .unlabeled: ("circle.dashed", .secondary)
        case .rough:     ("circle.lefthalf.filled", .orange)
        case .refined:   ("checkmark.circle.fill", .green)
        }
        return Image(systemName: icon)
            .foregroundStyle(color)
    }
}
