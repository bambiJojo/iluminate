//
//  AnalyzerView.swift
//  Ilumionate
//
//  The Analyzer tab — see, manage, and customize the AI analysis pipeline.
//  Three sections: Live Status, Library Intelligence, and Customize.
//

import SwiftUI

// MARK: - AnalyzerView

struct AnalyzerView: View {

    private var analysisManager: AnalysisStateManager { AnalysisStateManager.shared }
    @State private var prefs = AnalysisPreferences.shared
    @State private var audioFiles: [AudioFile] = []
    @State private var showingClearQueueConfirm = false
    @State private var customInstructionsText: String = AnalysisPreferences.shared.customInstructions

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            ScrollView {
                VStack(spacing: TranceSpacing.content) {
                    liveStatusSection
                    libraryIntelligenceSection
                    customizeSection
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.card)
                .padding(.bottom, TranceSpacing.tabBarClearance + 20)
            }
        }
        .navigationTitle("Analyzer")
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
        .onAppear { loadAudioFiles() }
    }

    // MARK: - Live Status

    private var liveStatusSection: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            sectionHeader("Live Status", symbol: "waveform")
            if let active = analysisManager.currentAnalysis {
                activeAnalysisCard(active)
            } else if analysisManager.analysisQueue.isEmpty {
                idleCard
            }
            if !analysisManager.analysisQueue.isEmpty {
                queueCard
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
                        Text(stageName(active.stage))
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.roseGold)
                    }
                    Spacer()
                    ProgressRing(progress: active.progress, size: 52)
                }
                ProgressView(value: active.progress)
                    .tint(Color.roseGold)
                    .animation(.easeInOut(duration: 0.3), value: active.progress)
                HStack {
                    Text("\(Int(active.progress * 100))% complete")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button("Cancel") { analysisManager.cancelCurrentAnalysis() }
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
                    Text("Queue · \(analysisManager.analysisQueue.count) file\(analysisManager.analysisQueue.count == 1 ? "" : "s")")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "list.number")
                        .foregroundStyle(Color.textSecondary)
                }
                Divider()
                ForEach(Array(analysisManager.analysisQueue.enumerated()), id: \.element.id) { index, file in
                    queueRow(file: file, position: index + 1)
                    if index < analysisManager.analysisQueue.count - 1 {
                        Divider().padding(.leading, 36)
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
                        analysisManager.prioritizeInQueue(audioFile: file)
                    } label: {
                        Image(systemName: "arrow.up.circle")
                            .foregroundStyle(Color.roseGold)
                    }
                }
                Button {
                    TranceHaptics.shared.light()
                    analysisManager.removeFromQueue(audioFile: file)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .font(.body)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Library Intelligence

    private var libraryIntelligenceSection: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            sectionHeader("Library Intelligence", symbol: "brain.head.profile")
            GlassCard {
                VStack(spacing: 16) {
                    statsRow
                    if !audioFiles.isEmpty {
                        Divider()
                        contentBreakdown
                    }
                    if !audioFiles.isEmpty {
                        Divider()
                        analysisReadinessRow
                    }
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(audioFiles.count)", label: "Files")
            statDivider
            statCell(value: "\(analyzedCount)", label: "Analyzed")
            statDivider
            statCell(value: "\(lightSyncReadyCount)", label: "Light Ready")
            statDivider
            statCell(
                value: audioFiles.isEmpty ? "–" : "\(Int(Double(analyzedCount) / Double(audioFiles.count) * 100))%",
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
                    Task { await queueAllUnanalyzed() }
                } label: {
                    Text("Analyze All")
                        .font(TranceTypography.caption.weight(.medium))
                        .foregroundStyle(Color.roseGold)
                }
            }
        }
    }

    // MARK: - Customize

    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            sectionHeader("Customize", symbol: "slider.horizontal.3")
            aiAnalysisGroup
            sessionGenerationGroup
            behaviorGroup
        }
    }

    private var aiAnalysisGroup: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                groupHeader("AI Analysis", symbol: "sparkles")
                Picker("Content Hint", selection: $prefs.contentHint) {
                    ForEach(ContentHint.allCases, id: \.self) { hint in
                        Label(hint.displayName, systemImage: hint.sfSymbol).tag(hint)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.roseGold)
                prefRow(
                    label: "Content Hint",
                    description: "Tells the AI what kind of content to expect, improving accuracy"
                )
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom AI Instructions")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                    TextEditor(text: $customInstructionsText)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                        .frame(height: 80)
                        .padding(8)
                        .background(Color.glassBorder.opacity(0.3))
                        .cornerRadius(8)
                        .onChange(of: customInstructionsText) {
                            prefs.customInstructions = customInstructionsText
                        }
                    Text("Added to the AI system prompt for every analysis")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary.opacity(0.7))
                }
            }
        }
    }

    private var sessionGenerationGroup: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                groupHeader("Session Generation", symbol: "waveform.path.ecg")
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Intensity")
                                .font(TranceTypography.body)
                                .foregroundStyle(Color.textPrimary)
                            Text("Overall brightness and strength of the light patterns")
                                .font(TranceTypography.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Text("\(Int(prefs.intensityMultiplier * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.roseGold)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Slider(value: $prefs.intensityMultiplier, in: 0.3...1.5)
                        .tint(Color.roseGold)
                    Divider()
                    pickerRow(
                        label: "Frequency Range",
                        description: "Hz range used when generating light moments",
                        selection: $prefs.frequencyProfile
                    )
                    Divider()
                    pickerRow(
                        label: "Transitions",
                        description: "How smoothly the light patterns change",
                        selection: $prefs.transitionStyle
                    )
                    Divider()
                    pickerRow(
                        label: "Color Temperature",
                        description: "Warmth or coolness of the light patterns",
                        selection: $prefs.colorTempMode
                    )
                    Divider()
                    Toggle(isOn: $prefs.bilateralMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bilateral Mode")
                                .font(TranceTypography.body)
                                .foregroundStyle(Color.textPrimary)
                            Text("Alternates stimulation between left and right visual fields")
                                .font(TranceTypography.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .tint(Color.roseGold)
                }
            }
        }
    }

    private var behaviorGroup: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                groupHeader("Behavior", symbol: "gearshape")
                Toggle(isOn: $prefs.autoAnalyzeOnImport) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Analyze on Import")
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textPrimary)
                        Text("Automatically queue new audio files for AI analysis when added to your library")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .tint(Color.roseGold)
            }
        }
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String, symbol: String) -> some View {
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

    private func groupHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Color.roseGold)
            Text(title)
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func prefRow(label: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(TranceTypography.body)
                .foregroundStyle(Color.textPrimary)
            Text(description)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func pickerRow<T: CaseIterable & Hashable & RawRepresentable>(
        label: String, description: String, selection: Binding<T>
    ) -> some View where T.AllCases: RandomAccessCollection, T.RawValue == String {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                Text(description)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Picker(label, selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { value in
                    Text(value.rawValue.capitalized).tag(value)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.roseGold)
            .labelsHidden()
        }
    }

    // MARK: - Computed Library Stats

    private var analyzedCount: Int {
        audioFiles.filter { $0.isAnalyzed }.count
    }

    private var lightSyncReadyCount: Int {
        let sessionsURL = URL.documentsDirectory.appendingPathComponent("GeneratedSessions", isDirectory: true)
        return audioFiles.filter { file in
            let base = file.displayName
            let url = sessionsURL.appendingPathComponent("\(base)_session.json")
            return FileManager.default.fileExists(atPath: url.path)
        }.count
    }

    private var unanalyzedCount: Int { audioFiles.count - analyzedCount }

    private var contentTypeCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for file in audioFiles {
            if let result = file.analysisResult {
                let key = result.contentType.rawValue
                counts[key, default: 0] += 1
            }
        }
        return counts
    }

    private var readinessMessage: String {
        let total = audioFiles.count
        guard total > 0 else { return "Add audio files to your library to begin" }
        let ready = lightSyncReadyCount
        if ready == total { return "All \(total) files have Light Sync sessions" }
        if unanalyzedCount == 0 { return "\(ready) of \(total) files have Light Sync sessions" }
        return "\(unanalyzedCount) file\(unanalyzedCount == 1 ? "" : "s") not yet analyzed"
    }

    // MARK: - Actions

    private func loadAudioFiles() {
        if let data = UserDefaults.standard.data(forKey: "audioFiles"),
           let files = try? JSONDecoder().decode([AudioFile].self, from: data) {
            audioFiles = files
        }
    }

    private func queueAllUnanalyzed() async {
        let unanalyzed = audioFiles.filter { !$0.isAnalyzed }
        await analysisManager.queueForAnalysis(unanalyzed)
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

    private func iconForContentType(_ type: String) -> String {
        switch type {
        case "hypnosis":       "eye.fill"
        case "meditation":     "leaf.fill"
        case "music":          "music.note"
        case "guidedImagery":  "photo.fill"
        case "affirmations":   "quote.bubble.fill"
        default:               "waveform"
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
        AnalyzerView()
    }
}
