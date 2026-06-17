//
//  TrainingWorkflowViews.swift
//  LumeLabel
//
//  Dataset-level workflow panel and progress sheet for analyzer training.
//

import SwiftUI
import AppKit

struct CorpusTrainingWorkflowPanel: View {
    let totalFileCount: Int
    let labeledFileCount: Int
    let workflow: TrainingWorkflowController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training Workflow")
                        .font(.headline)
                    Text(workflow.state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(workflow.state.title, systemImage: statusImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 12) {
                statChip(title: "Labeled", value: "\(labeledFileCount)/\(totalFileCount)")
                statChip(title: "Examples", value: "\(workflow.datasetSnapshot.validExampleCount)")
                statChip(
                    title: "Cache",
                    value: "\(workflow.datasetSnapshot.readyTranscriptCount)/\(workflow.datasetSnapshot.totalTranscriptCount)"
                )
            }

            HStack(spacing: 12) {
                statChip(title: "Hand", value: "\(workflow.datasetSnapshot.handLabeledExampleCount)")
                statChip(title: "Silver", value: "\(workflow.datasetSnapshot.silverLabeledExampleCount)")
                statChip(
                    title: "Phases",
                    value: "\(workflow.datasetSnapshot.coveredPhaseCount)/\(workflow.datasetSnapshot.totalPhaseCount)"
                )
            }

            if workflow.datasetSnapshot.validExampleCount > 0 {
                Text(workflow.datasetSnapshot.compactPhaseCoverageText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if workflow.isRunning, let progress = workflow.progressSnapshot {
                progressSummary(progress)
            }

            HStack(spacing: 8) {
                Button("Measure", systemImage: TrainingWorkflowAction.measure.systemImage) {
                    workflow.startMeasure()
                }
                .disabled(workflow.isRunning || workflow.datasetSnapshot.validExampleCount == 0)

                Button("Optimize", systemImage: TrainingWorkflowAction.optimize.systemImage) {
                    workflow.startOptimize()
                }
                .disabled(workflow.isRunning || workflow.datasetSnapshot.validExampleCount == 0)

                if workflow.resumableOptimization != nil {
                    Button("Resume Optimize", systemImage: "play.circle") {
                        workflow.resumeOptimize()
                    }
                    .disabled(workflow.isRunning)
                }

                Button("Reveal Whisper Cache", systemImage: "externaldrive") {
                    NSWorkspace.shared.open(AudioAnalyzer.whisperModelRepositoryURL())
                }
                .disabled(workflow.isRunning)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if workflow.datasetSnapshot.issueCount > 0 {
                Label(
                    "\(workflow.datasetSnapshot.issueCount) dataset issue\(workflow.datasetSnapshot.issueCount == 1 ? "" : "s")",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if let qualityWarning = workflow.datasetSnapshot.qualityWarning {
                Label(qualityWarning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let errorMessage = workflow.datasetSnapshot.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let resumableOptimization = workflow.resumableOptimization {
                Text(
                    "Paused at \(resumableOptimization.savedAt.formatted(date: .omitted, time: .shortened)) · \(resumableOptimization.detail)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let summary = workflow.lastRunSummary {
                Text(lastRunLine(for: summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top], 8)
        .padding(.bottom, 4)
    }

    private var statusImage: String {
        switch workflow.state {
        case .idle:
            return "bolt.horizontal.circle"
        case .preflighting:
            return "magnifyingglass"
        case .transcribing:
            return "waveform"
        case .measuring:
            return "chart.bar.xaxis"
        case .optimizing:
            return "slider.horizontal.3"
        case .paused:
            return "pause.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch workflow.state {
        case .completed:
            return .green
        case .paused:
            return .orange
        case .failed:
            return .red
        case .idle:
            return .secondary
        default:
            return .accentColor
        }
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.background, in: Capsule())
    }

    private func lastRunLine(for summary: TrainingWorkflowSummary) -> String {
        "\(summary.action.title) at \(summary.finishedAt.formatted(date: .omitted, time: .shortened)) · \(summary.evaluationMode.displayName) · \(summary.matchPercentage.formatted(.number.precision(.fractionLength(2))))% match"
    }

    private func progressSummary(_ progress: TrainingWorkflowProgressSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fractionCompleted = progress.fractionCompleted {
                ProgressView(value: fractionCompleted, total: 1)
                    .controlSize(.small)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            HStack(spacing: 10) {
                if let completedUnitCount = progress.completedUnitCount, let totalUnitCount = progress.totalUnitCount {
                    miniMetric(label: "Progress", value: "\(completedUnitCount)/\(totalUnitCount)")
                }
                miniMetric(label: "Elapsed", value: formatDuration(progress.elapsedTime))
                miniMetric(
                    label: progress.isEstimatedTotal ? "ETA (est.)" : "ETA",
                    value: progress.remainingTimeEstimate.map(formatDuration) ?? "Calculating…"
                )
            }
        }
    }

    private func miniMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}

struct TrainingWorkflowSheet: View {
    let workflow: TrainingWorkflowController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 440, idealWidth: 500, minHeight: 280)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(workflow.state.title)
                .font(.title3.weight(.semibold))
            Text(workflow.state.detail)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch workflow.state {
        case .preflighting, .measuring, .transcribing, .optimizing:
            runningContent
        case .paused(let snapshot):
            pausedContent(snapshot)
        case .completed(let summary):
            completedContent(summary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label("The training run did not finish.", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                if message.localizedCaseInsensitiveContains("WhisperKit") {
                    Button("Reveal Whisper Cache") {
                        reveal(url: AudioAnalyzer.whisperModelRepositoryURL(), opensParent: false)
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .idle:
            Text("Use the training controls in the corpus panel to begin.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var runningContent: some View {
        if let progress = workflow.progressSnapshot {
            VStack(alignment: .leading, spacing: 16) {
                if let fractionCompleted = progress.fractionCompleted {
                    ProgressView(value: fractionCompleted, total: 1)
                        .controlSize(.large)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(progress.message)
                        .font(.body)
                    if case .optimizing(let generation, _) = workflow.state, let generation {
                        Text("Generation \(generation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    trackerMetric(
                        title: "Progress",
                        value: progressCounts(progress) ?? "Starting…"
                    )
                    trackerMetric(
                        title: "Elapsed",
                        value: formatDuration(progress.elapsedTime)
                    )
                    trackerMetric(
                        title: progress.isEstimatedTotal ? "ETA (est.)" : "ETA",
                        value: progress.remainingTimeEstimate.map(formatDuration) ?? "Calculating…"
                    )
                }

                if progress.isEstimatedTotal {
                    Text("Optimize ETA is a moving estimate and may finish sooner if early stopping kicks in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func completedContent(_ summary: TrainingWorkflowSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                metricCard(title: "Examples", value: "\(summary.exampleCount)")
                metricCard(title: "Mode", value: summary.evaluationMode.displayName)
                metricCard(
                    title: "Match",
                    value: "\(summary.matchPercentage.formatted(.number.precision(.fractionLength(2))))%"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Outputs")
                    .font(.headline)
                outputButton(title: "Reveal Output Folder", url: summary.outputDirectoryURL, opensParent: false)
                outputButton(title: "Reveal Scorecard", url: summary.scorecardURL, opensParent: true)
                if let reportURL = summary.reportURL {
                    outputButton(title: "Reveal Report", url: reportURL, opensParent: true)
                }
                if let optimizedConfigURL = summary.optimizedConfigURL {
                    outputButton(title: "Reveal Optimized Config", url: optimizedConfigURL, opensParent: true)
                }
                if let activeConfigURL = summary.activeConfigURL {
                    outputButton(title: "Reveal Active Config", url: activeConfigURL, opensParent: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pausedContent(_ snapshot: TrainingWorkflowResumeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("The optimizer was paused safely and can be resumed later.", systemImage: "pause.circle.fill")
                .foregroundStyle(.orange)

            HStack(spacing: 12) {
                metricCard(
                    title: "Saved",
                    value: snapshot.savedAt.formatted(date: .omitted, time: .shortened)
                )
                metricCard(
                    title: "Generation",
                    value: snapshot.generation.map(String.init) ?? "Pending"
                )
            }

            Text(snapshot.detail)
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Outputs")
                    .font(.headline)
                outputButton(title: "Reveal Output Folder", url: snapshot.outputDirectoryURL, opensParent: false)
                outputButton(title: "Reveal Checkpoint", url: snapshot.checkpointURL, opensParent: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    private func outputButton(title: String, url: URL, opensParent: Bool) -> some View {
        Button(title) {
            reveal(url: url, opensParent: opensParent)
        }
        .buttonStyle(.link)
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if workflow.isRunning {
                if case .optimizing = workflow.state {
                    Button("Pause & Save") {
                        Task { await workflow.requestPause() }
                    }
                    .disabled(workflow.isPauseRequested)
                }

                Button("Cancel", role: .destructive) {
                    Task { await workflow.cancel() }
                }
            } else if workflow.resumableOptimization != nil {
                Button("Resume") {
                    workflow.resumeOptimize()
                }
            }
            Spacer()
            Button(workflow.isRunning ? "Hide" : "Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func reveal(url: URL, opensParent: Bool) {
        if opensParent {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func trackerMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }

    private func progressCounts(_ progress: TrainingWorkflowProgressSnapshot) -> String? {
        guard let completedUnitCount = progress.completedUnitCount, let totalUnitCount = progress.totalUnitCount else {
            return nil
        }
        return "\(completedUnitCount) / \(totalUnitCount)"
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let duration = max(0, Int(duration.rounded()))
    let hours = duration / 3600
    let minutes = (duration % 3600) / 60
    let seconds = duration % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}
