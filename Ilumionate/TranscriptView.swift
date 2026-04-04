//
//  TranscriptView.swift
//  Ilumionate
//
//  Full scrollable transcript with optional phase annotations.
//

import SwiftUI

struct TranscriptView: View {

    let transcript: String
    let analysisResult: AnalysisResult?
    let totalDuration: TimeInterval

    private var phases: [PhaseSegment]? { analysisResult?.hypnosisMetadata?.phases }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TranceSpacing.content) {
                // Phase bar at top (if available)
                if let result = analysisResult,
                   let phases, !phases.isEmpty {
                    PhaseTimelineBar(result: result, duration: totalDuration)
                        .frame(height: 16)
                        .padding(.horizontal, TranceSpacing.screen)

                    phaseLegend(phases)
                        .padding(.horizontal, TranceSpacing.screen)
                }

                // Full transcript text
                Text(transcript)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .padding(.horizontal, TranceSpacing.screen)

                Color.clear.frame(height: TranceSpacing.tabBarClearance)
            }
            .padding(.top, TranceSpacing.content)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
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
