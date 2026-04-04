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

            if workflow.datasetSnapshot.issueCount > 0 {
                Label(
                    "\(workflow.datasetSnapshot.issueCount) dataset issue\(workflow.datasetSnapshot.issueCount == 1 ? "" : "s")",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if let errorMessage = workflow.datasetSnapshot.errorMessage {
                Text(errorMessage)
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
        "\(summary.action.title) at \(summary.finishedAt.formatted(date: .omitted, time: .shortened)) · \(summary.matchPercentage.formatted(.number.precision(.fractionLength(2))))% match"
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
        case .preflighting, .measuring:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .transcribing(let current, let total, let filename):
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: Double(current), total: Double(max(total, 1)))
                Text("Working on \(filename)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .optimizing(let generation, let message):
            VStack(alignment: .leading, spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                if let generation {
                    Text("Generation \(generation)")
                        .font(.headline)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .completed(let summary):
            completedContent(summary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label("The training run did not finish.", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .idle:
            Text("Choose Measure or Optimize from the corpus toolbar to begin.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func completedContent(_ summary: TrainingWorkflowSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                metricCard(title: "Examples", value: "\(summary.exampleCount)")
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
                Button("Cancel", role: .destructive) {
                    Task { await workflow.cancel() }
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
}
