//
//  AnalyzerView.swift
//  Ilumionate
//
//  Library-wide analysis statistics.
//
//  This screen used to also own live status, the queue, the failure log, and
//  ready sessions. Those are now the Analysis Task Center, which projects one
//  shared task list instead of sampling the sources independently.
//
//  What is left is genuinely a different thing: statistics about the library
//  rather than the state of in-flight work. It is kept here, reachable from the
//  Task Center's toolbar, until it is relocated to Library — see the follow-up
//  task in the Phase 1 plan. Deleting it now would orphan a working feature to
//  satisfy a boundary.
//

import SwiftUI

// MARK: - AnalyzerView

struct AnalyzerView: View {

    @Bindable var engine: LightEngine

    @State private var audioFiles: [AudioFile] = []
    @State private var readySessionCount = 0

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            ScrollView {
                AnalyzerLibraryIntelligenceSection(
                    files: audioFiles,
                    lightSyncReadyCount: readySessionCount,
                    onAnalyzeAll: { Task { await queueAllUnanalyzed() } }
                )
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.card)
                .padding(.bottom, TranceSpacing.tabBarClearance + 20)
            }
        }
        .navigationTitle("Library Intelligence")
        .platformLargeNavigationTitle()
        .task { await loadAudioFiles() }
    }

    // MARK: - Actions

    private func loadAudioFiles() async {
        let loadedFiles = await AudioLibraryStore.loadRepairingStoredFiles()
        audioFiles = loadedFiles
        readySessionCount = GeneratedSessionStore.shared.readyCount(for: loadedFiles)
    }

    private func queueAllUnanalyzed() async {
        let unanalyzed = audioFiles.filter { !$0.isAnalyzed }
        await AnalysisStateManager.shared.queueForAnalysis(unanalyzed)
    }
}

// MARK: - Sections

private struct AnalyzerSectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.roseGold)
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .tracking(1.2)
        }
    }
}

private struct AnalyzerLibraryIntelligenceSection: View {
    let files: [AudioFile]
    let lightSyncReadyCount: Int
    let onAnalyzeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            AnalyzerSectionHeader(title: "Library Intelligence", symbol: "brain.head.profile")
            GlassCard {
                VStack(spacing: 16) {
                    statsRow
                    if !files.isEmpty {
                        Divider()
                        contentBreakdown
                    }
                    if !files.isEmpty {
                        Divider()
                        analysisReadinessRow
                    }
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(files.count)", label: "Files")
            statDivider
            statCell(value: "\(analyzedCount)", label: "Analyzed")
            statDivider
            statCell(value: "\(lightSyncReadyCount)", label: "Light Ready")
            statDivider
            statCell(
                value: files.isEmpty ? "–" : "\(Int(Double(analyzedCount) / Double(files.count) * 100))%",
                label: "Coverage"
            )
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.roseGold)
            Text(label)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Divider().frame(height: 36)
    }

    private var contentBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content Breakdown")
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
            ForEach(contentTypeCounts.sorted(by: { $0.value > $1.value }), id: \.key) { type, count in
                contentTypeRow(type: type, count: count, total: analyzedCount)
            }
        }
    }

    private func contentTypeRow(type: String, count: Int, total: Int) -> some View {
        let fraction = total > 0 ? Double(count) / Double(total) : 0
        return HStack(spacing: 8) {
            Image(systemName: iconForContentType(type))
                .font(.caption)
                .foregroundStyle(Color.roseGold)
                .frame(width: 16)
            Text(type.capitalized)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.glassBorder).frame(height: 4)
                    Capsule().fill(Color.roseGold).frame(width: geo.size.width * fraction, height: 4)
                }
            }
            .frame(width: 80, height: 4)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24, alignment: .trailing)
        }
    }

    private var analysisReadinessRow: some View {
        HStack {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Color.bwGamma)
                .font(.caption)
            Text(readinessMessage)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            if unanalyzedCount > 0 {
                Button {
                    onAnalyzeAll()
                } label: {
                    Text("Analyze All")
                        .font(TranceTypography.caption.weight(.medium))
                        .foregroundStyle(Color.roseGold)
                }
            }
        }
    }

    // MARK: - Derived Stats

    private var analyzedCount: Int {
        files.count(where: \.isAnalyzed)
    }

    private var unanalyzedCount: Int { files.count - analyzedCount }

    private var contentTypeCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for file in files {
            if let result = file.analysisResult {
                let key = result.contentType.rawValue
                counts[key, default: 0] += 1
            }
        }
        return counts
    }

    private var readinessMessage: String {
        let total = files.count
        guard total > 0 else { return "Add audio files to your library to begin" }
        let ready = lightSyncReadyCount
        if ready == total { return "All \(total) files have Light Sync sessions" }
        if unanalyzedCount == 0 { return "\(ready) of \(total) files have Light Sync sessions" }
        return "\(unanalyzedCount) file\(unanalyzedCount == 1 ? "" : "s") not yet analyzed"
    }

    private func iconForContentType(_ type: String) -> String {
        switch AudioContentType.parse(type) {
        case .hypnosis: return "eye.fill"
        case .eroticHypnosis: return "flame.fill"
        case .sleepHypnosis: return "moon.zzz.fill"
        case .meditation: return "leaf.fill"
        case .brainwave: return "waveform.path.ecg"
        case .asmr: return "ear"
        case .music: return "music.note"
        case .guidedImagery: return "photo.fill"
        case .affirmations: return "quote.bubble.fill"
        case .unknown: return "waveform"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AnalyzerView(engine: LightEngine())
    }
}
