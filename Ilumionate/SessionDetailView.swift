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
    private var catalogEntry: KnownAudioCatalogEntry? {
        KnownAudioCatalog.shared.match(audioFile: audioFile)?.entry
    }
    private var hasReviewedGoldScore: Bool {
        guard let catalogEntry else { return false }
        return catalogEntry.goldLightScore.evidenceKind != .catalogMetadata
    }

    init(audioFile: AudioFile, engine: LightEngine) {
        self.engine = engine
        self.audioFileID = audioFile.id
        _audioFile = State(initialValue: audioFile)
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: TranceSpacing.content) {
                    headerSection
                    playCTASection
                    if audioFile.isAnalyzed {
                        if let phases, !phases.isEmpty {
                            phaseTimelineSection(phases)
                        }
                        if let lightSession {
                            lightScorePreviewSection(lightSession)
                        }
                        if analysis?.expertAnalysis != nil {
                            expertAnalysisSection
                        }
                        analysisInsightsSection
                    }
                    if let transcript, !transcript.isEmpty {
                        transcriptPreviewSection(transcript)
                    }
                    if audioFile.isAnalyzed == false {
                        // Generic session-arc preview when there is no analyzed
                        // phase data yet (the real PhaseTimelineBar shows once analyzed).
                        LiminalCard(label: "Phases") {
                            PhaseTimeline(current: nil)
                        }
                        analyzeNowSection
                    }
                    reanalyzeSection
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.bottom, TranceSpacing.tabBarClearance + TranceSpacing.content)
            }
        }
        .navigationTitle(audioFile.displayName)
        .platformLargeNavigationTitle()
        .platformFullScreenCover(isPresented: $showingPlayer) {
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
            UsageAnalytics.shared.screen(.sessionDetail)
        }
        .onChange(of: AnalysisStateManager.shared.completedAnalyses.count) {
            refreshAudioFile()
            loadLightSession()
        }
        .onChange(of: AnalysisStateManager.shared.partialResultsRevision) {
            refreshAudioFile()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        LiminalCard {
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
                            if let creator = audioFile.creatorDisplayName {
                                Text(creator)
                                Text("·")
                            }
                            Label(audioFile.durationFormatted, systemImage: "clock")
                            if let type = analysis?.contentType {
                                Text("·")
                                Text(type.displayName)
                            }
                        }
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()
                }

                if !audioFile.discoveredThemes.isEmpty {
                    Label(
                        audioFile.discoveredThemes.joined(separator: " · "),
                        systemImage: "tag"
                    )
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                }

                // Analysis status badge
                if audioFile.isAnalyzed {
                    HStack(spacing: TranceSpacing.inner) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.roseGold)
                        Text(analysisProvenanceLabel)
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
                } else if audioFile.hasTranscription {
                    HStack(spacing: TranceSpacing.inner) {
                        Image(systemName: "text.quote")
                            .foregroundStyle(Color.bwAlpha)
                        Text("Transcript ready · analysis continuing")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.bwAlpha)
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
        GlowButton(
            title: lightSession != nil ? "Play with Light Sync" : "Play",
            systemImage: "play.fill"
        ) {
            showingPlayer = true
        }
    }

    // MARK: - Phase Timeline

    private func phaseTimelineSection(_ phases: [PhaseSegment]) -> some View {
        LiminalCard(label: "Phase Timeline") {
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
        LiminalCard(label: "Transcript") {
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
        LiminalCard(
            label: catalogEntry.map {
                "Gold Light Score · v\($0.goldLightScore.scoreVersion)"
            } ?? "Light Score"
        ) {
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

    private var expertAnalysisSection: some View {
        Group {
            if let expert = analysis?.expertAnalysis {
                LiminalCard(label: "Expert Analysis") {
                    VStack(alignment: .leading, spacing: TranceSpacing.list) {
                        HStack(alignment: .center, spacing: TranceSpacing.list) {
                            ZStack {
                                Circle()
                                    .fill(expertVerdictColor(expert.verdict).opacity(0.18))
                                    .frame(width: 48, height: 48)
                                Image(systemName: expertVerdictIcon(expert.verdict))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(expertVerdictColor(expert.verdict))
                            }

                            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                                Text(expert.verdict.displayName)
                                    .font(TranceTypography.body.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Text(
                                    "\(expert.qualityScore, format: .percent.precision(.fractionLength(0))) \(catalogEntry == nil ? "analyzer quality" : "score quality")"
                                )
                                    .font(TranceTypography.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }

                            Spacer()
                        }

                        Text(expert.summary)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)

                        if !expert.findings.isEmpty {
                            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                                Text("Evidence")
                                    .font(TranceTypography.caption.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                ForEach(expert.findings.prefix(4)) { finding in
                                    expertFindingRow(finding)
                                }
                            }
                        }

                        if !expert.improvementActions.isEmpty {
                            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                                Text("Improve The Analyzer")
                                    .font(TranceTypography.caption.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                ForEach(expert.improvementActions.prefix(3)) { action in
                                    expertActionRow(action)
                                }
                            }
                        }

                        if !expert.reviewMoments.isEmpty {
                            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                                Text("Review Moments")
                                    .font(TranceTypography.caption.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                ForEach(expert.reviewMoments.prefix(4)) { moment in
                                    HStack(spacing: TranceSpacing.inner) {
                                        Text(formatTime(moment.time))
                                            .font(TranceTypography.caption.monospacedDigit())
                                            .foregroundStyle(Color.roseGold)
                                            .frame(width: 48, alignment: .leading)
                                        Text(moment.phase?.displayName ?? "Gap")
                                            .font(TranceTypography.caption.weight(.medium))
                                            .foregroundStyle(Color.textPrimary)
                                        Text(moment.reason)
                                            .font(TranceTypography.caption)
                                            .foregroundStyle(Color.textSecondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var analysisInsightsSection: some View {
        LiminalCard(
            label: hasReviewedGoldScore
                ? "Gold Review"
                : (catalogEntry == nil ? "AI Insights" : "Catalog Review")
        ) {
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

    /// Credits whichever path actually produced the analysis. Claiming "AI
    /// Analyzed" after the model declined and keyword classification stood in
    /// contradicts the AI Insights card directly below it.
    private var analysisProvenanceLabel: String {
        if hasReviewedGoldScore { return "Gold Standard" }
        if catalogEntry != nil { return "Catalog Template" }
        return analysis?.usedKeywordFallback == true ? "Keyword Analysis" : "AI Analyzed"
    }

    private var analyzeNowSection: some View {
        LiminalCard {
            VStack(spacing: TranceSpacing.card) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.roseGold)

                Text("Analyze this file to unlock phase timeline, transcript, and AI-generated light sessions.")
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                // Reading the manager here means the button swaps to live progress
                // the moment work is queued, rather than looking as though the tap
                // did nothing.
                if AnalysisStateManager.shared.isQueuedOrActive(audioFile) {
                    analyzingIndicator
                } else {
                    GlowButton(title: "Analyze Now", systemImage: "sparkles") {
                        Task {
                            AnalysisStateManager.shared.evictCachedResult(for: audioFile)
                            await AnalysisStateManager.shared.queueForAnalysis(audioFile)
                        }
                    }
                }
            }
        }
    }

    private var analyzingIndicator: some View {
        let active = AnalysisStateManager.shared.currentAnalysis
        let isThisFile = active?.audioFile.id == audioFile.id
        return HStack(spacing: TranceSpacing.list) {
            ProgressView()
                .controlSize(.small)
            Text(stageText(active: active, isThisFile: isThisFile))
                .font(TranceTypography.body)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TranceSpacing.card)
        .accessibilityElement(children: .combine)
    }

    private func stageText(active: ActiveAnalysis?, isThisFile: Bool) -> String {
        guard isThisFile, let active else { return "Waiting in queue…" }
        return AnalysisStageFeedback.stageSummary(active.stage)
    }

    // MARK: - Re-analyze

    private var reanalyzeSection: some View {
        Group {
            if audioFile.isAnalyzed && catalogEntry == nil {
                Button {
                    TranceHaptics.shared.light()
                    Task {
                        AnalysisStateManager.shared.evictCachedResult(for: audioFile)
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
        guard let updated = AudioLibraryStore.load().first(where: { $0.id == audioFileID }) else {
            return
        }

        audioFile = updated
    }

    private func loadLightSession() {
        lightSession = GeneratedSessionStore.shared.load(for: audioFile)
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

    private func expertFindingRow(_ finding: ExpertAnalysis.Finding) -> some View {
        HStack(alignment: .top, spacing: TranceSpacing.inner) {
            Image(systemName: expertSeverityIcon(finding.severity))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(expertSeverityColor(finding.severity))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                    .font(TranceTypography.caption.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                Text(finding.detail)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            }
        }
    }

    private func expertActionRow(_ action: ExpertAnalysis.ImprovementAction) -> some View {
        HStack(alignment: .top, spacing: TranceSpacing.inner) {
            Text("P\(action.priority)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.roseGold)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(TranceTypography.caption.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                Text(action.detail)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            }
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
        case .eroticHypnosis: return .roseDeep
        case .sleepHypnosis: return .bwDelta
        case .meditation:    return .bwAlpha
        case .brainwave:     return .bwGamma
        case .asmr:          return .warmAccent
        case .music:         return .bwBeta
        case .guidedImagery: return .bwTheta
        case .affirmations:  return .warmAccent
        default:             return .roseGold
        }
    }

    private var contentTypeIcon: String {
        switch analysis?.contentType {
        case .hypnosis:      return "brain.head.profile"
        case .eroticHypnosis: return "flame"
        case .sleepHypnosis: return "moon.zzz"
        case .meditation:    return "leaf"
        case .brainwave:     return "waveform.path.ecg"
        case .asmr:          return "ear"
        case .music:         return "music.note"
        case .guidedImagery: return "figure.mind.and.body"
        case .affirmations:  return "quote.bubble"
        default:             return "waveform"
        }
    }

    private func expertVerdictIcon(_ verdict: ExpertAnalysis.Verdict) -> String {
        switch verdict {
        case .productionReady: return "checkmark.seal.fill"
        case .reviewRecommended: return "exclamationmark.triangle.fill"
        case .needsRelabeling: return "xmark.octagon.fill"
        }
    }

    private func expertVerdictColor(_ verdict: ExpertAnalysis.Verdict) -> Color {
        switch verdict {
        case .productionReady: return .roseGold
        case .reviewRecommended: return .warmAccent
        case .needsRelabeling: return .roseDeep
        }
    }

    private func expertSeverityIcon(_ severity: ExpertAnalysis.Severity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    private func expertSeverityColor(_ severity: ExpertAnalysis.Severity) -> Color {
        switch severity {
        case .info: return .roseGold
        case .warning: return .warmAccent
        case .critical: return .roseDeep
        }
    }

    private func phaseColor(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .induction:    return .phaseInduction
        case .fractionation:return .phaseFractionation
        case .deepening:    return .phaseDeepener
        case .confusion:    return .mint
        case .therapy, .suggestions: return .phaseSuggestion
        case .eroticSuggestions: return .roseDeep
        case .brainwashing: return .orange
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
