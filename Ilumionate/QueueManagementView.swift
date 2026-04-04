//
//  QueueManagementView.swift
//  Ilumionate
//
//  Queue management interface for audio analysis
//

import SwiftUI

// Conditional Glass button style helper for backward compatibility
extension View {
    @ViewBuilder
    func glassButtonStyleIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(GlassButtonStyle())
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// View for managing the audio analysis queue
struct QueueManagementView: View {

    @Bindable var analysisManager: AnalysisStateManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary
                    .ignoresSafeArea()
                
                Group {
                    if analysisManager.analysisQueue.isEmpty {
                        emptyQueueView
                    } else {
                        queueListView
                    }
                }
            }
            .navigationTitle("Analysis Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .glassButtonStyleIfAvailable()
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !analysisManager.analysisQueue.isEmpty {
                        Button("Clear All") {
                            analysisManager.clearQueue()
                        }
                        .foregroundStyle(Color.red)
                        .glassButtonStyleIfAvailable()
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyQueueView: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            // Hypnotic icon with dreamy glow
            ZStack {
                Circle()
                    .fill(Color.lavender.opacity(0.3))
                    .frame(width: 120, height: 120)

                Image(systemName: "tray.circle")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: TranceSpacing.list) {
                Text("No Files Queued")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.primary)

                Text("Analysis queue is empty")
                    .font(TranceTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Queue List

    private var queueListView: some View {
        List {
            // Current analysis section
            if let currentAnalysis = analysisManager.currentAnalysis {
                Section {
                    CurrentAnalysisRow(analysis: currentAnalysis)
                } header: {
                    Text("Currently Analyzing")
                }
            }

            // Queue section
            if !analysisManager.analysisQueue.isEmpty {
                Section {
                    ForEach(Array(analysisManager.analysisQueue.enumerated()), id: \.element.id) { index, file in
                        QueueFileRow(
                            file: file,
                            position: index + 1,
                            isFirst: index == 0,
                            isLast: index == analysisManager.analysisQueue.count - 1,
                            analysisManager: analysisManager
                        )
                    }
                } header: {
                    Text("Queued (\(analysisManager.analysisQueue.count))")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Current Analysis Row

struct CurrentAnalysisRow: View {
    let analysis: ActiveAnalysis

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Stage icon with progress ring
                ZStack {
                    Circle()
                        .stroke(Color.lavender.opacity(0.3), lineWidth: 3)
                        .frame(width: 40, height: 40)

                    Circle()
                        .trim(from: 0, to: analysis.progress)
                        .stroke(Color.bwGamma, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 40, height: 40)
                        .animation(.easeInOut(duration: 0.5), value: analysis.progress)

                    Image(systemName: analysis.stage.icon)
                        .font(.caption)
                        .foregroundStyle(analysis.stage.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.audioFile.filename)
                        .font(TranceTypography.sectionTitle)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack {
                        Image(systemName: analysis.stage.icon)
                            .font(.caption2)
                        Text(analysis.stage.title)
                            .font(TranceTypography.caption)
                    }
                    .foregroundStyle(Color.roseDeep)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(analysis.progress * 100))%")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.bwGamma)
                        .fontWeight(.semibold)

                    Text("Complete")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            ProgressView(value: analysis.progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: Color.bwGamma))
                .scaleEffect(y: 0.5)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, TranceSpacing.list)
        .background(
            LinearGradient(
                colors: [
                    Color.roseGold.opacity(0.4),
                    Color.lavender.opacity(0.2)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(TranceRadius.thumbnail)
    }
}

// MARK: - Queue File Row

struct QueueFileRow: View {
    let file: AudioFile
    let position: Int
    let isFirst: Bool
    let isLast: Bool
    let analysisManager: AnalysisStateManager

    var body: some View {
        HStack(spacing: 12) {
            // Queue position
            Text("\(position)")
                .font(TranceTypography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.lavender.opacity(0.4))
                .clipShape(Circle())

            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(file.filename)
                    .font(TranceTypography.sectionTitle)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Label(file.durationFormatted, systemImage: "clock")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.secondary)

                    Label(file.fileSizeFormatted, systemImage: "doc")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Queue controls
            HStack(spacing: 8) {
                // Move up button
                Button {
                    analysisManager.moveUpInQueue(audioFile: file)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(TranceTypography.caption)
                        .foregroundStyle(isFirst ? .secondary : Color.roseDeep)
                }
                .disabled(isFirst)
                .glassButtonStyleIfAvailable()

                // Move down button
                Button {
                    analysisManager.moveDownInQueue(audioFile: file)
                } label: {
                    Image(systemName: "arrow.down")
                        .font(TranceTypography.caption)
                        .foregroundStyle(isLast ? .secondary : Color.roseDeep)
                }
                .disabled(isLast)
                .glassButtonStyleIfAvailable()

                // Remove button
                Button {
                    analysisManager.removeFromQueue(audioFile: file)
                } label: {
                    Image(systemName: "trash")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.red)
                }
                .glassButtonStyleIfAvailable()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, TranceSpacing.list)
        .background(Color.white.opacity(0.6))
        .cornerRadius(TranceRadius.thumbnail)
    }
}

// MARK: - AnalysisStage Extension for Icons

extension AnalysisStage {
    var icon: String {
        switch self {
        case .starting:
            return "play.circle"
        case .transcribing:
            return "waveform"
        case .analyzing:
            return "brain.head.profile"
        case .generatingSession:
            return "lightbulb"
        case .complete:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
}

#Preview {
    QueueManagementView(analysisManager: AnalysisStateManager.shared)
}
