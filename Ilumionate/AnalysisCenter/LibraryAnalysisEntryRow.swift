//
//  LibraryAnalysisEntryRow.swift
//  Ilumionate
//
//  Library's entry into the Analysis Center. Replaces
//  LibraryAnalysisStatusSection, which sampled the same sources independently
//  and truncated them differently, so it could disagree with the pill and the
//  queue about what was happening.
//

import SwiftUI

struct LibraryAnalysisEntryRow: View {
    let activeTask: AnalysisTask?
    let queuedCount: Int
    let attentionCount: Int
    let onOpen: () -> Void

    var body: some View {
        if hasAnything {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                LibraryShelfSectionHeader(title: "Personal Audio Analysis") {
                    onOpen()
                }

                Button(action: onOpen) {
                    LiminalCard {
                        HStack(spacing: TranceSpacing.list) {
                            Image(systemName: attentionCount > 0 ? "exclamationmark.triangle.fill" : "waveform")
                                .font(.title3)
                                .foregroundStyle(attentionCount > 0 ? Color.roseDeep : Color.roseGold)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary)
                                    .font(TranceTypography.body)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                if let activeTask {
                                    Text(activeTask.audioFile.displayName)
                                        .font(TranceTypography.caption)
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: TranceSpacing.inner)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textLight)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(summary)
                .accessibilityHint("Opens the analysis center")
            }
        }
    }

    private var hasAnything: Bool {
        activeTask != nil || queuedCount > 0 || attentionCount > 0
    }

    private var summary: String {
        var parts: [String] = []
        if activeTask != nil { parts.append("Analyzing") }
        if queuedCount > 0 { parts.append("\(queuedCount) queued") }
        if attentionCount > 0 {
            parts.append(attentionCount == 1 ? "1 needs attention" : "\(attentionCount) need attention")
        }
        return parts.joined(separator: " · ")
    }
}
