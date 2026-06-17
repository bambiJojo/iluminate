//
//  TranscriptView.swift
//  Ilumionate
//
//  Full scrollable transcript with optional phase annotations and timeline
//  phrase inspection.
//

import SwiftUI

struct TranscriptView: View {

    let transcript: String
    let analysisResult: AnalysisResult?
    let totalDuration: TimeInterval

    @State private var selectedTimelineWindowID: UUID?

    private var phases: [PhaseSegment]? { analysisResult?.hypnosisMetadata?.phases }
    private var transcriptAnalysis: TranscriptAnalysis? { analysisResult?.transcriptAnalysis }
    private var timelineWindows: [TranscriptSectionMetrics] { transcriptAnalysis?.timelineWindows ?? [] }

    private var selectedTimelineWindow: TranscriptSectionMetrics? {
        if let selectedTimelineWindowID,
           let selected = timelineWindows.first(where: { $0.id == selectedTimelineWindowID }) {
            return selected
        }
        return preferredTimelineWindow
    }

    private var preferredTimelineWindow: TranscriptSectionMetrics? {
        timelineWindows.first(where: { !$0.waymarkerMatches.isEmpty }) ?? timelineWindows.first
    }

    private var phraseKnowledge: CorpusPhaseKnowledge {
        CorpusPhaseKnowledgeCache.shared.knowledge()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TranceSpacing.content) {
                if let result = analysisResult,
                   let phases, !phases.isEmpty {
                    PhaseTimelineBar(result: result, duration: totalDuration)
                        .frame(height: 16)
                        .padding(.horizontal, TranceSpacing.screen)

                    phaseLegend(phases)
                        .padding(.horizontal, TranceSpacing.screen)
                }

                if let transcriptAnalysis, !transcriptAnalysis.timelineWindows.isEmpty {
                    phraseTimelineSection(transcriptAnalysis)
                        .padding(.horizontal, TranceSpacing.screen)
                }

                GlassCard(label: "Transcript") {
                    Text(transcript)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, TranceSpacing.screen)

                Color.clear.frame(height: TranceSpacing.tabBarClearance)
            }
            .padding(.top, TranceSpacing.content)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PhraseLibraryView()
                } label: {
                    Label("Phrase Library", systemImage: "books.vertical")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .onAppear(perform: synchronizeTimelineSelection)
        .onChange(of: timelineWindows.map(\.id)) {
            synchronizeTimelineSelection()
        }
    }

    private func synchronizeTimelineSelection() {
        guard let preferredTimelineWindow else {
            selectedTimelineWindowID = nil
            return
        }
        guard let selectedTimelineWindowID,
              timelineWindows.contains(where: { $0.id == selectedTimelineWindowID }) else {
            self.selectedTimelineWindowID = preferredTimelineWindow.id
            return
        }
    }

    // MARK: - Phrase Timeline

    private func phraseTimelineSection(_ transcriptAnalysis: TranscriptAnalysis) -> some View {
        GlassCard(label: "Phrase Timeline") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Text("Bars represent merged transcript windows. Tap a window to inspect the phrases and hypnosis way-markers shaping the analyzer read.")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)

                timelineSummaryRow(transcriptAnalysis)

                NavigationLink {
                    PhraseLibraryView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical")
                        Text("Browse Full Phrase Library")
                            .font(TranceTypography.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(Color.roseGold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.roseGold.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(transcriptAnalysis.timelineWindows) { window in
                            Button {
                                selectedTimelineWindowID = window.id
                            } label: {
                                timelineWindowBar(
                                    window,
                                    selected: selectedTimelineWindowID == window.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let selectedTimelineWindow {
                    selectedWindowDetail(selectedTimelineWindow)
                }
            }
        }
    }

    private func timelineSummaryRow(_ transcriptAnalysis: TranscriptAnalysis) -> some View {
        let waymarkerWindows = transcriptAnalysis.timelineWindows.filter { !$0.waymarkerMatches.isEmpty }.count
        return HStack(spacing: TranceSpacing.inner) {
            timelineBadge(
                title: "Windows",
                value: transcriptAnalysis.timelineWindows.count.formatted(),
                tint: Color.phaseDeepener
            )
            timelineBadge(
                title: "Way-Markers",
                value: waymarkerWindows.formatted(),
                tint: Color.roseGold
            )
            if let strongest = transcriptAnalysis.timelineWindows.max(by: {
                $0.normalizedWordsPerMinute < $1.normalizedWordsPerMinute
            }) {
                timelineBadge(
                    title: "Peak Pace",
                    value: "\(Int(strongest.wordsPerMinute.rounded())) WPM",
                    tint: phaseColor(strongest.phase ?? strongest.waymarkerMatches.first?.phase ?? .transitional)
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func timelineBadge(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(TranceTypography.cardLabel)
                .foregroundStyle(Color.textLight)
            Text(value)
                .font(TranceTypography.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }

    private func timelineWindowBar(
        _ window: TranscriptSectionMetrics,
        selected: Bool
    ) -> some View {
        let maxWordsPerMinute = max(timelineWindows.map(\.wordsPerMinute).max() ?? 1, 1)
        let heightRatio = max(0.18, min(window.wordsPerMinute / maxWordsPerMinute, 1.0))
        let barColor = phaseColor(window.phase ?? window.waymarkerMatches.first?.phase ?? .transitional)

        return VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.12 : 0.06))
                    .frame(width: 34, height: 122)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [barColor.opacity(0.45), barColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 34, height: 26 + (96 * heightRatio))

                if !window.waymarkerMatches.isEmpty {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.roseGold)
                        .padding(.bottom, 104)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? barColor.opacity(0.9) : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1)
            )
            .shadow(color: selected ? barColor.opacity(0.28) : .clear, radius: 12, y: 6)

            Text(formatTime(window.startTime))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(selected ? Color.textPrimary : Color.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.phase?.displayName ?? "Transcript") section starting at \(formatTime(window.startTime))")
        .accessibilityValue("\(Int(window.wordsPerMinute.rounded())) words per minute")
    }

    private func selectedWindowDetail(_ window: TranscriptSectionMetrics) -> some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            Divider()

            HStack(alignment: .top, spacing: TranceSpacing.inner) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(window.phase?.displayName ?? window.waymarkerMatches.first?.phase.displayName ?? "Timeline Window")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("\(formatTime(window.startTime)) – \(formatTime(window.endTime))")
                        .font(TranceTypography.caption.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Text(window.waymarkerMatches.isEmpty ? "Merged Window" : "Way-Markers Active")
                    .font(TranceTypography.caption.weight(.semibold))
                    .foregroundStyle(window.waymarkerMatches.isEmpty ? Color.textSecondary : Color.roseGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill((window.waymarkerMatches.isEmpty ? Color.white : Color.roseGold).opacity(0.10))
                    )
            }

            HStack(spacing: TranceSpacing.inner) {
                detailMetric(title: "Words", value: window.wordCount.formatted())
                detailMetric(title: "Pace", value: "\(Int(window.wordsPerMinute.rounded())) WPM")
                detailMetric(title: "Speech", value: window.speechCoverage.formatted(.percent.precision(.fractionLength(0))))
            }

            if !window.waymarkerMatches.isEmpty {
                chipSection(
                    title: "Way-Markers",
                    subtitle: "Detected phrases tied to known hypnosis transitions",
                    items: window.waymarkerMatches.prefix(6).map { match in
                        TimelineChipItem(
                            id: "waymarker|\(match.phase.rawValue)|\(match.phrase)",
                            text: match.phrase,
                            detail: match.phase.displayName,
                            tint: phaseColor(match.phase)
                        )
                    }
                )
            }

            if !window.topDistinctivePhrases.isEmpty || !window.topPhrases.isEmpty {
                let phrases = Array((window.topDistinctivePhrases + window.topPhrases).prefix(8))
                chipSection(
                    title: "Top Phrases",
                    subtitle: "The strongest repeated language inside this merged window",
                    items: phrases.map { phrase in
                        TimelineChipItem(
                            id: "phrase|\(phrase.phrase)",
                            text: phrase.phrase,
                            detail: "x\(phrase.count)",
                            tint: Color.phaseDeepener
                        )
                    }
                )
            }

            let libraryMatches = libraryMatches(for: window)
            if !libraryMatches.isEmpty {
                chipSection(
                    title: "Phrase Library Matches",
                    subtitle: "Known phase phrases from the training corpus and curated hypnosis references",
                    items: libraryMatches.prefix(8).map { match in
                        TimelineChipItem(
                            id: "library|\(match.phase.rawValue)|\(match.phrase)",
                            text: match.phrase,
                            detail: match.detailLabel,
                            tint: phaseColor(match.phase)
                        )
                    }
                )
            }

            if !window.topDistinctiveWords.isEmpty {
                chipSection(
                    title: "Distinctive Words",
                    subtitle: "Vocabulary standing out against the rest of this file",
                    items: window.topDistinctiveWords.prefix(10).map { word in
                        TimelineChipItem(
                            id: "word|\(word.word)",
                            text: word.word,
                            detail: String(format: "%.1fx", word.normalizedShareLift),
                            tint: Color.phaseSuggestion
                        )
                    }
                )
            }
        }
    }

    private func detailMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(TranceTypography.cardLabel)
                .foregroundStyle(Color.textLight)
            Text(value)
                .font(TranceTypography.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func chipSection(
        title: String,
        subtitle: String,
        items: [TimelineChipItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TranceTypography.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            FlexibleChipCloud(items: items)
        }
    }

    private func libraryMatches(for window: TranscriptSectionMetrics) -> [PhraseLibraryMatch] {
        let phrasePool = Set(window.topPhrases.map(\.phrase) + window.topDistinctivePhrases.map(\.phrase))
        guard !phrasePool.isEmpty else { return [] }

        return phraseKnowledge.phraseAssociations
            .flatMap { phase, associations in
                associations.compactMap { association in
                    guard phrasePool.contains(association.phrase) else { return nil }
                    return PhraseLibraryMatch(
                        phrase: association.phrase,
                        phase: phase,
                        origin: association.origin,
                        sourceLabel: association.sourceLabel,
                        weight: association.weight
                    )
                }
            }
            .sorted { lhs, rhs in
                if abs(lhs.weight - rhs.weight) < 0.0001 { return lhs.phrase < rhs.phrase }
                return lhs.weight > rhs.weight
            }
    }

    // MARK: - Phase Legend

    private func phaseLegend(_ phases: [PhaseSegment]) -> some View {
        VStack(alignment: .leading, spacing: TranceSpacing.micro) {
            ForEach(phases) { segment in
                HStack(spacing: TranceSpacing.inner) {
                    Circle()
                        .fill(phaseColor(segment.phase))
                        .frame(width: 6, height: 6)
                    Text(segment.phase.displayName)
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func phaseColor(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .induction: return .phaseInduction
        case .fractionation: return .phaseFractionation
        case .deepening: return .phaseDeepener
        case .confusion: return .mint
        case .therapy, .suggestions: return .phaseSuggestion
        case .eroticSuggestions: return .roseDeep
        case .brainwashing: return .orange
        case .emergence: return .bwBeta
        case .preTalk: return .bwAlpha
        case .conditioning: return .bwGamma
        case .transitional: return .textLight
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = time >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: time) ?? "0:00"
    }
}

private struct PhraseLibraryMatch: Identifiable {
    var id: String { "\(phase.rawValue)|\(phrase)" }

    let phrase: String
    let phase: HypnosisMetadata.Phase
    let origin: HypnosisPhraseEvidenceOrigin
    let sourceLabel: String?
    let weight: Double

    var originLabel: String {
        switch origin {
        case .curated:
            return "research"
        case .corpus:
            return "corpus"
        case .blended:
            return "blended"
        }
    }

    var detailLabel: String {
        if let sourceLabel, !sourceLabel.isEmpty {
            return "\(phase.displayName) · \(originLabel) · \(sourceLabel)"
        }
        return "\(phase.displayName) · \(originLabel)"
    }
}

private struct TimelineChipItem: Identifiable {
    let id: String
    let text: String
    let detail: String
    let tint: Color
}

private struct FlexibleChipCloud: View {
    let items: [TimelineChipItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(chunkedItems.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.text)
                                .font(TranceTypography.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(item.tint.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(item.tint.opacity(0.20), lineWidth: 1)
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var chunkedItems: [[TimelineChipItem]] {
        stride(from: 0, to: items.count, by: 3).map { startIndex in
            Array(items[startIndex..<min(startIndex + 3, items.count)])
        }
    }
}
