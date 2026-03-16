//
//  AnalyzedSessionsSection.swift
//  Ilumionate
//
//  Shows analyzed audio files in the Analyzer tab as cards with a phase
//  timeline thumbnail — a horizontal colored bar where each segment's color
//  represents its hypnosis phase (intro, induction, deepening, therapy,
//  suggestions, anchoring, emergence).
//

import SwiftUI

// MARK: - Section

struct AnalyzedSessionsSection: View {
    let audioFiles: [AudioFile]

    private var analyzedFiles: [AudioFile] {
        audioFiles
            .filter { $0.isAnalyzed }
            .sorted { ($0.createdDate) > ($1.createdDate) }
    }

    var body: some View {
        if !analyzedFiles.isEmpty {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.below.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.roseGold)
                    Text("ANALYZED SESSIONS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .tracking(1.2)
                    Spacer()
                    Text("\(analyzedFiles.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
                VStack(spacing: TranceSpacing.list) {
                    ForEach(analyzedFiles) { file in
                        AnalyzedSessionCard(file: file)
                    }
                }
            }
        }
    }
}

// MARK: - Card

struct AnalyzedSessionCard: View {
    let file: AudioFile

    private var result: AnalysisResult? { file.analysisResult }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                if let result {
                    PhaseTimelineBar(result: result, duration: file.duration)
                    if result.contentType == .hypnosis,
                       let phases = result.hypnosisMetadata?.phases, !phases.isEmpty {
                        PhaseLegendRow(phases: phases)
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconFor(result?.contentType))
                .font(.subheadline)
                .foregroundStyle(colorFor(result?.contentType))
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(subtitleFor(result))
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(file.durationFormatted)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func subtitleFor(_ result: AnalysisResult?) -> String {
        guard let result else { return "Analyzed" }
        let typeName = result.contentType.rawValue.capitalized
        if !result.recommendedPreset.isEmpty {
            return "\(typeName) · \(result.recommendedPreset)"
        }
        return typeName
    }

    private func iconFor(_ type: AnalysisResult.ContentType?) -> String {
        switch type {
        case .hypnosis:      return "eye.fill"
        case .meditation:    return "leaf.fill"
        case .music:         return "music.note"
        case .guidedImagery: return "photo.fill"
        case .affirmations:  return "quote.bubble.fill"
        default:             return "waveform"
        }
    }

    private func colorFor(_ type: AnalysisResult.ContentType?) -> Color {
        switch type {
        case .hypnosis:      return Color.phaseDeepener
        case .meditation:    return Color.bwTheta
        case .music:         return Color.bwBeta
        case .guidedImagery: return Color.phaseInduction
        case .affirmations:  return Color.warmAccent
        default:             return Color.textSecondary
        }
    }
}

// MARK: - Phase Timeline Bar

/// Full-width horizontal bar where each segment is colored by its hypnosis phase.
/// Non-hypnosis files show a content-type gradient.
struct PhaseTimelineBar: View {
    let result: AnalysisResult
    let duration: TimeInterval

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                if let phases = result.hypnosisMetadata?.phases,
                   !phases.isEmpty, duration > 0 {
                    ForEach(phases) { seg in
                        let segDuration = max(0, seg.endTime - seg.startTime)
                        let fraction = segDuration / duration
                        let width = max(3, geo.size.width * CGFloat(fraction))
                        Rectangle()
                            .fill(colorFor(seg.phase))
                            .frame(width: width)
                    }
                } else {
                    LinearGradient(
                        colors: gradientFor(result.contentType),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        }
        .frame(height: 10)
        .clipShape(.rect(cornerRadius: 5))
    }

    private func colorFor(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .preTalk:      return Color.phaseIntro
        case .induction:    return Color.phaseInduction
        case .deepening:    return Color.phaseDeepener
        case .therapy:      return Color.phaseDeepener.opacity(0.7)
        case .suggestions:  return Color.phaseSuggestion
        case .conditioning: return Color.phaseFractionation
        case .emergence:    return Color.phaseAwakening
        case .transitional: return Color.textSecondary.opacity(0.5)
        }
    }

    private func gradientFor(_ type: AnalysisResult.ContentType) -> [Color] {
        switch type {
        case .meditation:
            return [Color.bwAlpha.opacity(0.6), Color.bwTheta, Color.bwAlpha.opacity(0.6)]
        case .music:
            return [Color.bwBeta.opacity(0.5), Color.bwGamma, Color.bwBeta.opacity(0.5)]
        case .guidedImagery:
            return [Color.phaseInduction.opacity(0.6), Color.phaseDeepener.opacity(0.6), Color.phaseInduction.opacity(0.6)]
        case .affirmations:
            return [Color.warmAccent.opacity(0.5), Color.roseGold.opacity(0.7), Color.warmAccent.opacity(0.5)]
        default:
            return [Color.textSecondary.opacity(0.3), Color.textSecondary.opacity(0.5)]
        }
    }
}

// MARK: - Phase Legend

/// Small dot + short name legend showing unique phases present in the session.
struct PhaseLegendRow: View {
    let phases: [PhaseSegment]

    private var uniquePhases: [HypnosisMetadata.Phase] {
        var seen = Set<HypnosisMetadata.Phase>()
        return phases.compactMap { seg in
            guard !seen.contains(seg.phase) else { return nil }
            seen.insert(seg.phase)
            return seg.phase
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(uniquePhases, id: \.self) { phase in
                HStack(spacing: 4) {
                    Circle()
                        .fill(colorFor(phase))
                        .frame(width: 6, height: 6)
                    Text(shortName(phase))
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
        }
    }

    private func colorFor(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .preTalk:      return Color.phaseIntro
        case .induction:    return Color.phaseInduction
        case .deepening:    return Color.phaseDeepener
        case .therapy:      return Color.phaseDeepener.opacity(0.7)
        case .suggestions:  return Color.phaseSuggestion
        case .conditioning: return Color.phaseFractionation
        case .emergence:    return Color.phaseAwakening
        case .transitional: return Color.textSecondary.opacity(0.5)
        }
    }

    private func shortName(_ phase: HypnosisMetadata.Phase) -> String {
        switch phase {
        case .preTalk:      return "Intro"
        case .induction:    return "Induction"
        case .deepening:    return "Deepening"
        case .therapy:      return "Therapy"
        case .suggestions:  return "Suggestions"
        case .conditioning: return "Anchoring"
        case .emergence:    return "Awakening"
        case .transitional: return "Transition"
        }
    }
}
