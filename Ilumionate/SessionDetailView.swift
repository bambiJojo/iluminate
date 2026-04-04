//
//  SessionDetailView.swift
//  Ilumionate
//
//  Rich detail view for an audio file showing AI analysis results:
//  phase timeline, transcript preview, light score, and playback CTA.
//

import SwiftUI

struct SessionDetailView: View {
    let engine: LightEngine
    private let audioFileID: AudioFile.ID

    @State private var lightSession: LightSession?
    @State private var showingPlayer = false
    @State private var showingReanalyze = false
    @State private var audioFile: AudioFile

    private var analysis: AnalysisResult? { audioFile.analysisResult }
    private var phases: [PhaseSegment]? { analysis?.hypnosisMetadata?.phases }
    private var transcript: String? { audioFile.transcription }

    init(audioFile: AudioFile, engine: LightEngine) {
        self.engine = engine
        self.audioFileID = audioFile.id
        _audioFile = State(initialValue: audioFile)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.content) {
                headerSection
                playCTASection
                if audioFile.isAnalyzed {
                    if let phases, !phases.isEmpty {
                        phaseTimelineSection(phases)
                    }
                    if let transcript, !transcript.isEmpty {
                        transcriptPreviewSection(transcript)
                    }
                    if let lightSession {
                        lightScorePreviewSection(lightSession)
                    }
                    analysisInsightsSection
                } else {
                    analyzeNowSection
                }
                reanalyzeSection
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.bottom, TranceSpacing.tabBarClearance + TranceSpacing.content)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle(audioFile.displayName)
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $showingPlayer) {
            if let session = lightSession {
                UnifiedPlayerView(
                    mode: .session(session: session, audioFile: audioFile),
                    engine: engine
                )
            } else {
                UnifiedPlayerView(
                    mode: .audioLight(audioFile: audioFile),
                    engine: engine
                )
            }
        }
        .onAppear {
            refreshAudioFile()
            loadLightSession()
        }
        .onChange(of: AnalysisStateManager.shared.completedAnalyses.count) {
            refreshAudioFile()
            loadLightSession()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    // Content type badge
                    ZStack {
                        RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                            .fill(contentTypeColor.opacity(0.18))
                            .frame(width: 56, height: 56)
                        Image(systemName: contentTypeIcon)
                            .font(.system(size: 24))
                            .foregroundStyle(contentTypeColor)
                    }

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(audioFile.displayName)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: TranceSpacing.inner) {
                            Label(audioFile.durationFormatted, systemImage: "clock")
                            if let type = analysis?.contentType {
                                Text("·")
                                Text(type.rawValue.capitalized)
                            }
                        }
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()
                }

                // Analysis status badge
                if audioFile.isAnalyzed {
                    HStack(spacing: TranceSpacing.inner) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.roseGold)
                        Text("AI Analyzed")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.roseGold)

                        if let confidence = analysis?.classificationConfidence?.overallConfidence {
                            Text("·")
                                .foregroundStyle(Color.textLight)
                            Text("\(confidence, format: .percent.precision(.fractionLength(0))) confidence")
                                .font(TranceTypography.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                } else {
                    HStack(spacing: TranceSpacing.inner) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .foregroundStyle(Color.textSecondary)
                        Text("Not yet analyzed")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Play CTA

    private var playCTASection: some View {
        Button {
            TranceHaptics.shared.heavy()
            showingPlayer = true
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text(lightSession != nil ? "Play with Light Sync" : "Play")
                    .bold()
            }
            .font(TranceTypography.sectionTitle)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TranceSpacing.card)
            .background(
                LinearGradient(
                    colors: [.roseGold, .roseDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(.rect(cornerRadius: TranceRadius.button))
            .shadow(
                color: TranceShadow.button.color,
                radius: TranceShadow.button.radius,
                x: TranceShadow.button.x,
                y: TranceShadow.button.y
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Phase Timeline

    private func phaseTimelineSection(_ phases: [PhaseSegment]) -> some View {
        GlassCard(label: "Phase Timeline") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                // Color-coded horizontal bar (reuses existing component)
                if let result = analysis {
                    PhaseTimelineBar(result: result, duration: audioFile.duration)
                        .frame(height: 24)
                }

                // Phase legend
                ForEach(phases) { segment in
                    HStack(spacing: TranceSpacing.inner) {
                        Circle()
                            .fill(phaseColor(segment.phase))
                            .frame(width: 8, height: 8)
                        Text(segment.phase.displayName)
                            .font(TranceTypography.caption)
                            .bold()
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(formatTimeRange(segment.startTime, segment.endTime))
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Transcript Preview

    private func transcriptPreviewSection(_ text: String) -> some View {
        GlassCard(label: "Transcript") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Text(String(text.prefix(300)) + (text.count > 300 ? "..." : ""))
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(8)

                NavigationLink {
                    TranscriptView(
                        transcript: text,
                        analysisResult: analysis,
                        totalDuration: audioFile.duration
                    )
                } label: {
                    HStack {
                        Text("See Full Transcript")
                            .font(TranceTypography.caption)
                            .bold()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.roseGold)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Light Score Preview

    private func lightScorePreviewSection(_ session: LightSession) -> some View {
        GlassCard(label: "Light Score") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                // Mini frequency curve
                LightScoreMiniGraph(moments: session.light_score, duration: session.duration_sec)
                    .frame(height: 60)

                HStack(spacing: TranceSpacing.card) {
                    StatBadge(
                        label: "Moments",
                        value: "\(session.light_score.count)"
                    )
                    StatBadge(
                        label: "Duration",
                        value: session.durationFormatted
                    )
                    if let first = session.light_score.first {
                        StatBadge(
                            label: "Start Hz",
                            value: first.frequency.formatted(.number.precision(.fractionLength(1)))
                        )
                    }
                }

                NavigationLink {
                    LightScoreEditorView(session: session, audioFile: audioFile)
                } label: {
                    HStack {
                        Text("View Light Score")
                            .font(TranceTypography.caption)
                            .bold()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color.roseGold)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Analysis Insights

    private var analysisInsightsSection: some View {
        GlassCard(label: "AI Insights") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                if let summary = analysis?.aiSummary, !summary.isEmpty {
                    Text(summary)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                }

                if let mood = analysis?.mood {
                    insightRow(label: "Mood", value: mood.rawValue.capitalized, icon: "face.smiling")
                }
                if let energy = analysis?.energyLevel {
                    insightRow(label: "Energy", value: energy.formatted(.percent.precision(.fractionLength(0))), icon: "bolt")
                }
                if let preset = analysis?.recommendedPreset, !preset.isEmpty {
                    insightRow(label: "Preset", value: preset, icon: "wand.and.stars")
                }
                if let depth = analysis?.hypnosisMetadata?.estimatedTranceDeph {
                    insightRow(label: "Trance Depth", value: depth.rawValue.capitalized, icon: "brain.head.profile")
                }
                if let style = analysis?.hypnosisMetadata?.inductionStyle {
                    insightRow(label: "Induction", value: style.rawValue.capitalized, icon: "person.wave.2")
                }
            }
        }
    }

    // MARK: - Analyze Now (unanalyzed files)

    private var analyzeNowSection: some View {
        GlassCard {
            VStack(spacing: TranceSpacing.card) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.roseGold)

                Text("Analyze this file to unlock phase timeline, transcript, and AI-generated light sessions.")
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    TranceHaptics.shared.medium()
                    Task {
                        await AnalysisStateManager.shared.queueForAnalysis(audioFile)
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Analyze Now")
                            .bold()
                    }
                    .font(TranceTypography.body)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TranceSpacing.list)
                    .background(Color.roseGold)
                    .clipShape(.rect(cornerRadius: TranceRadius.button))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Re-analyze

    private var reanalyzeSection: some View {
        Group {
            if audioFile.isAnalyzed {
                Button {
                    TranceHaptics.shared.light()
                    Task {
                        await AnalysisStateManager.shared.queueForAnalysis(audioFile)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Re-analyze")
                    }
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TranceSpacing.list)
                    .background(Color.glassBorder.opacity(0.1))
                    .clipShape(.rect(cornerRadius: TranceRadius.button))
                    .overlay(
                        RoundedRectangle(cornerRadius: TranceRadius.button)
                            .strokeBorder(Color.glassBorder.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func refreshAudioFile() {
        guard let data = UserDefaults.standard.data(forKey: AnalysisStateManager.audioFilesUserDefaultsKey),
              let files = try? JSONDecoder().decode([AudioFile].self, from: data),
              let updated = files.first(where: { $0.id == audioFileID }) else {
            return
        }

        audioFile = updated
    }

    private func loadLightSession() {
        let sessionsURL = URL.documentsDirectory.appending(path: "GeneratedSessions")
        let baseName = audioFile.filename
            .replacing(".mp3", with: "")
            .replacing(".m4a", with: "")
            .replacing(".wav", with: "")
            .replacing(".aac", with: "")
        let fileURL = sessionsURL.appending(path: "\(baseName)_session.json")
        if let data = try? Data(contentsOf: fileURL),
           let session = try? JSONDecoder().decode(LightSession.self, from: data) {
            lightSession = session
        }
    }

    private func insightRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: TranceSpacing.inner) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.roseGold)
                .frame(width: 20)
            Text(label)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(TranceTypography.caption)
                .bold()
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func formatTimeRange(_ start: TimeInterval, _ end: TimeInterval) -> String {
        "\(formatTime(start)) – \(formatTime(end))"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    private var contentTypeColor: Color {
        switch analysis?.contentType {
        case .hypnosis:      return .bwDelta
        case .meditation:    return .bwAlpha
        case .music:         return .bwBeta
        case .guidedImagery: return .bwTheta
        case .affirmations:  return .warmAccent
        default:             return .roseGold
        }
    }

    private var contentTypeIcon: String {
        switch analysis?.contentType {
        case .hypnosis:      return "brain.head.profile"
        case .meditation:    return "leaf"
        case .music:         return "music.note"
        case .guidedImagery: return "figure.mind.and.body"
        case .affirmations:  return "quote.bubble"
        default:             return "waveform"
        }
    }

    private func phaseColor(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .induction:    return .phaseInduction
        case .deepening:    return .phaseDeepener
        case .therapy, .suggestions: return .phaseSuggestion
        case .emergence:    return .bwBeta
        case .preTalk:      return .bwAlpha
        case .conditioning: return .bwGamma
        case .transitional: return .textLight
        }
    }
}

// MARK: - Light Score Mini Graph

struct LightScoreMiniGraph: View {
    let moments: [LightMoment]
    let duration: Double

    var body: some View {
        Canvas { ctx, size in
            guard moments.count >= 2, duration > 0 else { return }

            let maxFreq = moments.map(\.frequency).max() ?? 1
            let path = Path { p in
                for (i, moment) in moments.enumerated() {
                    let x = (moment.time / duration) * size.width
                    let y = size.height - (moment.frequency / maxFreq) * size.height * 0.9
                    if i == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }

            ctx.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [.roseGold, .bwTheta]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                lineWidth: 2
            )
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(TranceTypography.body)
                .bold()
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TranceSpacing.inner)
        .background(Color.glassBorder.opacity(0.08))
        .clipShape(.rect(cornerRadius: TranceRadius.tabItem))
    }
}
