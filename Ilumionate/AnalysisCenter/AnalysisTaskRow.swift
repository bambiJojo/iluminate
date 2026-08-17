//
//  AnalysisTaskRow.swift
//  Ilumionate
//
//  One task, in any of its six states, with the actions that state allows.
//  All failure copy comes from AnalysisFailurePresentation so the stable
//  user-facing strings stay in one place.
//

import SwiftUI

struct AnalysisTaskRow: View {
    let task: AnalysisTask
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onRemoveFromQueue: () -> Void
    let onDismissFailure: () -> Void
    let onRemoveFailure: () -> Void
    let onPlay: () -> Void

    @State private var showingRemoveConfirmation = false

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                header
                if let detail = detailText {
                    Text(detail)
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let recovery = recoveryText {
                    Label(recovery, systemImage: "arrow.counterclockwise.circle")
                        .font(.caption2)
                        .foregroundStyle(Color.bwAlpha)
                }
                actions
            }
        }
        .confirmationDialog(
            "Remove saved progress?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Saved Progress", role: .destructive, action: onRemoveFailure)
            Button("Cancel", role: .cancel) {}
        } message: {
            // Naming what is destroyed, and what is not. The audio file is the
            // thing a user will fear losing.
            Text("This deletes the saved analysis progress for “\(task.audioFile.displayName)” — the transcript or analysis a retry would have resumed from. Your audio file is not deleted.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.audioFile.displayName)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(statusText)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: TranceSpacing.inner)

            if case .running(_, let progress, _) = task.state {
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(TranceTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.roseGold)
            }
            if case .preparing(let download) = task.state {
                Text(download.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                    .font(TranceTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.roseGold)
            }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        switch task.state {
        case .queued:
            HStack(spacing: TranceSpacing.list) {
                Button("Remove from Queue", systemImage: "minus.circle", action: onRemoveFromQueue)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case .preparing, .running:
            Button("Cancel", systemImage: "xmark.circle", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .paused:
            Button("Retry", systemImage: "arrow.counterclockwise", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(Color.roseGold)
                .controlSize(.small)
        case .failed:
            HStack(spacing: TranceSpacing.list) {
                if task.lastFailure?.presentation.canRetry == true {
                    Button("Retry", systemImage: "arrow.counterclockwise", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(Color.roseGold)
                        .controlSize(.small)
                }
                if task.lastFailure?.dismissedAt == nil {
                    Button("Dismiss", systemImage: "eye.slash", action: onDismissFailure)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button("Remove", systemImage: "trash", role: .destructive) {
                    showingRemoveConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .ready:
            Button("Play", systemImage: "play.fill", action: onPlay)
                .buttonStyle(.borderedProminent)
                .tint(Color.roseGold)
                .controlSize(.small)
        }
    }

    // MARK: Presentation

    private var symbol: String {
        switch task.state {
        case .queued:            "clock"
        case .preparing:         "arrow.down.circle"
        case .running:           "waveform"
        case .paused:            "pause.circle"
        case .failed:            "exclamationmark.triangle.fill"
        case .ready:             "waveform.badge.checkmark"
        }
    }

    private var tint: Color {
        switch task.state {
        case .failed:            .roseDeep
        case .ready:             .bwGamma
        case .queued, .paused:   .textSecondary
        case .preparing, .running: .roseGold
        }
    }

    private var statusText: String {
        switch task.state {
        case .queued(let position):
            "Waiting in queue · position \(position)"
        case .preparing:
            "Preparing analyzer"
        case .running(let stage, _, _):
            AnalysisStageFeedback.stageSummary(stage)
        case .paused:
            task.recovery == .none ? "Paused" : "Paused · progress saved"
        case .failed:
            task.lastFailure?.presentation.title ?? "Analysis paused"
        case .ready:
            "Analysis complete · Light Sync ready"
        }
    }

    private var detailText: String? {
        guard case .failed = task.state, let failure = task.lastFailure else { return nil }
        return failure.presentation.message
    }

    private var recoveryText: String? {
        guard case .failed = task.state, let failure = task.lastFailure else { return nil }
        return failure.presentation.statusMessage ?? failure.presentation.recoveryMessage
    }
}
