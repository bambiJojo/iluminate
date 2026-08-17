//
//  AnalysisStatusPill.swift
//  Ilumionate
//
//  Ambient analysis signal in the bottom chrome. Replaces AnalysisStatusOverlay
//  and AnalysisRecoveryStatusOverlay, which shared one slot and so could never
//  show active work and a failure at the same time.
//
//  Deliberate divergence from the Task Center's tier order: there, an
//  action-required failure outranks active work. Applied literally here it would
//  take the headline and hide live progress for as long as a manual failure
//  existed — reintroducing the defect this replaces. Progress is transient and
//  self-resolving; a failure is a standing decision, so it gets a chip instead.
//

import SwiftUI

struct AnalysisStatusPill: View {
    let activeTask: AnalysisTask?
    let queuedCount: Int
    let attentionCount: Int
    let onTap: () -> Void

    var body: some View {
        Button {
            TranceHaptics.shared.light()
            onTap()
        } label: {
            HStack(spacing: TranceSpacing.inner) {
                leading

                Spacer(minLength: TranceSpacing.inner)

                if queuedCount > 0 {
                    Text("+\(queuedCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.roseGold.opacity(0.8))
                        .clipShape(.capsule)
                }

                if attentionCount > 0 {
                    Label("\(attentionCount)", systemImage: "exclamationmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.roseDeep)
                }
            }
            .padding(.horizontal, TranceSpacing.card)
            .padding(.vertical, TranceSpacing.inner)
            .background(.ultraThinMaterial)
            .background(Color.bgCard)
            .clipShape(.rect(cornerRadius: TranceRadius.tabItem))
            .overlay {
                RoundedRectangle(cornerRadius: TranceRadius.tabItem)
                    .strokeBorder(Color.roseGold.opacity(0.3), lineWidth: 1)
            }
            .padding(.horizontal, TranceSpacing.screen)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the analysis center")
    }

    @ViewBuilder
    private var leading: some View {
        if let activeTask {
            ProgressView()
                .controlSize(.small)
                .tint(.roseGold)
            VStack(alignment: .leading, spacing: 2) {
                Text(activeTask.audioFile.displayName)
                    .font(TranceTypography.caption)
                    .bold()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(detail(for: activeTask))
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.roseGold)
            Text("Analysis needs attention")
                .font(TranceTypography.caption)
                .bold()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
    }

    private func detail(for task: AnalysisTask) -> String {
        switch task.state {
        case .preparing:
            "Preparing analyzer"
        case .running(let stage, _, _):
            AnalysisStageFeedback.stageSummary(stage)
        default:
            ""
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let activeTask {
            parts.append("Analyzing \(activeTask.audioFile.displayName)")
        }
        if queuedCount > 0 { parts.append("\(queuedCount) queued") }
        if attentionCount > 0 { parts.append("\(attentionCount) need attention") }
        return parts.isEmpty ? "Analysis status" : parts.joined(separator: ", ")
    }
}
