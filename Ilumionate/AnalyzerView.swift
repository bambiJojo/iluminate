//
//  AnalyzerView.swift
//  Ilumionate
//
//  Queue management view for the AI analysis pipeline.
//  Two sections: Live Status and Library Intelligence.
//

import SwiftUI

// MARK: - AnalyzerView

struct AnalyzerView: View {

    @Bindable var engine: LightEngine

    @State private var analysisManager = AnalysisStateManager.shared
    @State private var audioFiles: [AudioFile] = []
    @State private var readySessions: [SyncPlayerItem] = []
    @State private var showingClearQueueConfirm = false
    @State private var readyPlayerItem: SyncPlayerItem?


    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            ScrollView {
                VStack(spacing: TranceSpacing.content) {
                    AnalyzerLiveStatusSection(manager: analysisManager)
                    if !readyFiles.isEmpty {
                        AnalysisReadySessionsCard(
                            files: readyFiles,
                            onPlay: playReadySession
                        )
                    }
                    AnalyzerLibraryIntelligenceSection(
                        files: audioFiles,
                        onAnalyzeAll: { Task { await queueAllUnanalyzed() } }
                    )
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.card)
                .padding(.bottom, TranceSpacing.tabBarClearance + 20)
            }
        }
        .navigationTitle("Analysis Queue")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if analysisManager.currentAnalysis != nil || !analysisManager.analysisQueue.isEmpty {
                    Button(role: .destructive) { showingClearQueueConfirm = true } label: {
                        Label("Clear Queue", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.roseGold)
                }
            }
        }
        .confirmationDialog("Clear all queued analyses?", isPresented: $showingClearQueueConfirm,
                            titleVisibility: .visible) {
            Button("Clear Queue", role: .destructive) { analysisManager.clearQueue() }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await analysisManager.restoreManualRecoveries()
            await loadAudioFiles()
            UsageAnalytics.shared.screen(.analysisQueue)
        }
        .onChange(of: analysisManager.completedAnalyses.count) {
            Task { await loadAudioFiles() }
        }
        .fullScreenCover(item: $readyPlayerItem) { item in
            if let session = item.lightSession {
                UnifiedPlayerView(
                    mode: .session(session: session, audioFile: item.audioFile),
                    engine: engine
                )
            }
        }
    }

    // MARK: - Actions

    private func loadAudioFiles() async {
        let loadedFiles = await AudioLibraryStore.loadRepairingStoredFiles()
        audioFiles = loadedFiles
        readySessions = loadedFiles
            .sorted { $0.createdDate > $1.createdDate }
            .compactMap { file in
                guard let session = GeneratedSessionStore.shared.load(for: file) else { return nil }
                return SyncPlayerItem(audioFile: file, lightSession: session)
            }
    }

    private func queueAllUnanalyzed() async {
        let unanalyzed = audioFiles.filter { !$0.isAnalyzed }
        await analysisManager.queueForAnalysis(unanalyzed)
    }

    private var readyFiles: [AudioFile] {
        readySessions.map(\.audioFile)
    }

    private func playReadySession(_ file: AudioFile) {
        guard let item = readySessions.first(where: { $0.audioFile.id == file.id }) else { return }
        TranceHaptics.shared.medium()
        UsageAnalytics.shared.analysisReadyAction(.play)
        readyPlayerItem = item
    }
}

// MARK: - Analyzer Sections

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

private struct AnalyzerLiveStatusSection: View {
    let manager: AnalysisStateManager

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            AnalyzerSectionHeader(title: "Live Status", symbol: "waveform")
            if let active = manager.currentAnalysis {
                activeAnalysisCard(active)
            } else if manager.analysisQueue.isEmpty {
                idleCard
            }
            if !manager.analysisQueue.isEmpty {
                queueCard
            }
            if !manager.failedAnalyses.isEmpty {
                failureLogCard
            }
        }
    }

    private func activeAnalysisCard(_ active: ActiveAnalysis) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(active.audioFile.displayName)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(AnalysisStageFeedback.stageSummary(active.stage))
                            .font(TranceTypography.caption)
                            .foregroundStyle(active.stage == .failed ? .red : Color.roseGold)
                        if active.stage == .failed {
                            Text("See the recovery options below.")
                                .font(TranceTypography.caption)
                                .foregroundStyle(.red.opacity(0.8))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    ProgressRing(progress: active.progress, size: 52)
                }
                ProgressView(value: active.progress)
                    .tint(Color.roseGold)
                    .animation(.easeInOut(duration: 0.3), value: active.progress)
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    if let estimate = AnalysisStageFeedback.estimatedRemainingText(
                        progress: active.progress,
                        elapsed: context.date.timeIntervalSince(active.startedAt)
                    ) {
                        Text("\(estimate). You can leave this screen; processing continues in the background.")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack {
                    Text("\(Int(active.progress * 100))% complete")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button("Cancel") { manager.cancelCurrentAnalysis() }
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.roseGold)
                }
            }
        }
    }

    private var idleCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.bwGamma)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to Analyze")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Queue a file to begin AI analysis")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var queueCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Queue · \(manager.analysisQueue.count) file\(manager.analysisQueue.count == 1 ? "" : "s")")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "list.number")
                        .foregroundStyle(Color.textSecondary)
                }
                Divider()
                ForEach(Array(manager.analysisQueue.enumerated()), id: \.element.id) { index, file in
                    queueRow(file: file, position: index + 1)
                    if index < manager.analysisQueue.count - 1 {
                        Divider().padding(.leading, 36)
                    }
                }
            }
        }
    }

    private var failureLogCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("Recent Failures · \(manager.failedAnalyses.count)")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                }
                Divider()
                ForEach(manager.failedAnalyses.suffix(5)) { failure in
                    AnalysisFailureRow(failure: failure) {
                        Task { await manager.retryFailedAnalysis(failure) }
                    }
                }
            }
        }
    }

    private func queueRow(file: AudioFile, position: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(position)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(file.durationFormatted)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            HStack(spacing: 16) {
                if position > 1 {
                    Button {
                        TranceHaptics.shared.light()
                        manager.prioritizeInQueue(audioFile: file)
                    } label: {
                        Image(systemName: "arrow.up.circle")
                            .foregroundStyle(Color.roseGold)
                    }
                }
                Button {
                    TranceHaptics.shared.light()
                    manager.removeFromQueue(audioFile: file)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .font(.body)
        }
        .padding(.vertical, 2)
    }

    private func stageName(_ stage: AnalysisStage) -> String {
        switch stage {
        case .starting:           "Starting…"
        case .transcribing:       "Transcribing"
        case .analyzing:          "Analyzing"
        case .generatingSession:  "Generating Session"
        case .complete:           "Complete"
        case .failed:             "Failed"
        }
    }
}

private struct AnalysisFailureRow: View {
    let failure: FailedAnalysis
    let onRetry: () -> Void

    private var presentation: AnalysisFailurePresentation { failure.presentation }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(failure.audioFile.displayName)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(presentation.title)
                        .font(TranceTypography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red.opacity(0.9))
                }
                Spacer()
                if let status = presentation.statusMessage {
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.roseGold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.roseGold.opacity(0.12), in: Capsule())
                }
            }

            Text(presentation.message)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
            Text(presentation.recoveryMessage)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)

            if presentation.canRetry {
                Button(failure.retryState == .automatic ? "Retry Now" : "Retry") {
                    TranceHaptics.shared.light()
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.roseGold)
                .accessibilityHint("Continues from saved analysis progress when available")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

private struct AnalyzerLibraryIntelligenceSection: View {
    let files: [AudioFile]
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

    private var lightSyncReadyCount: Int {
        GeneratedSessionStore.shared.readyCount(for: files)
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

// MARK: - Progress Ring

private struct ProgressRing: View {
    let progress: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.glassBorder, lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.roseGold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
            Text("\(Int(progress * 100))%")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AnalyzerView(engine: LightEngine())
    }
}
