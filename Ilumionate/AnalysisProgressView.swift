//
//  AnalysisProgressView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import SwiftUI

/// Shows the progress of audio analysis and displays results
struct AnalysisProgressView: View {

    let audioFile: AudioFile
    @State private var viewModel = AnalysisProgressViewModel()
    @Environment(\.dismiss) private var dismiss

    var onAnalysisComplete: (AudioFile, AnalysisResult) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: 30) {

                    Spacer()

                    // Progress visualization
                    progressSection

                    // Stage indicator
                    stageIndicator

                    Spacer()

                    // Results or error
                    if let result = viewModel.analysisResult {
                        resultsPreview(result)
                    } else if let error = viewModel.errorMessage {
                        errorView(error)
                    }

                    Spacer()

                    // Action button
                    actionButton

                }
                .padding()
            }
            .navigationTitle("Analyzing Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        cancelAnalysis()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                    .disabled(viewModel.stage == .complete)
                }
            }
            .task {
                await viewModel.startAnalysis(for: audioFile)
            }
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 20) {
            // Animated progress circle with hypnotic effects
            ZStack {
                Circle()
                    .stroke(Color.lavender.opacity(0.3), lineWidth: 8)
                    .frame(width: 150, height: 150)

                Circle()
                    .trim(from: 0, to: viewModel.overallProgress)
                    .stroke(
                        viewModel.stage == .complete ? Color.green : Color.bwGamma,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.overallProgress)

                // Rotating background spiral
                Circle()
                    .stroke(Color.roseDeep.opacity(0.2), lineWidth: 2)
                    .frame(width: 180, height: 180)

                // Icon or percentage
                if viewModel.stage == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(Color.green)
                } else if viewModel.stage == .failed {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(Color.red)
                } else {
                    VStack(spacing: 4) {
                        Text("\(Int(viewModel.overallProgress * 100))%")
                            .font(TranceTypography.greetingAccent)
                            .foregroundStyle(.primary)

                        // Show spinner to indicate activity
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color.bwGamma)
                    }
                }
            }
        }
    }

    // MARK: - Stage Indicator

    private var stageIndicator: some View {
        VStack(spacing: 12) {
            // Current stage title
            Text(viewModel.stage.title)
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(.primary)

            // Stage description
            Text(viewModel.stage.description)
                .font(TranceTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Progress bar for current stage
            if viewModel.stage != .complete && viewModel.stage != .failed {
                ProgressView(value: viewModel.currentStageProgress)
                    .tint(Color.bwGamma)
                    .frame(width: 200)
            }
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(TranceRadius.thumbnail)
    }

    // MARK: - Results Preview

    private func resultsPreview(_ result: AnalysisResult) -> some View {
        VStack(spacing: 16) {
            Text("Analysis Complete!")
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.green)

            // Quick summary
            VStack(alignment: .leading, spacing: 8) {
                resultRow(icon: "brain.head.profile", label: "Mood", value: result.mood.rawValue.capitalized)
                resultRow(icon: "bolt.fill", label: "Energy", value: "\(Int(result.energyLevel * 100))%")
                resultRow(icon: "waveform", label: "Frequency",
                         value: "\(Int(result.suggestedFrequencyRange.lowerBound))-\(Int(result.suggestedFrequencyRange.upperBound)) Hz")
                resultRow(icon: "light.max", label: "Intensity", value: "\(Int(result.suggestedIntensity * 100))%")
            }
            .padding()
            .background(Color.roseDeep.opacity(0.4))
            .cornerRadius(TranceRadius.thumbnail)
        }
    }

    private func resultRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(TranceTypography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label)
                .font(TranceTypography.body)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.red)

            Text("Analysis Failed")
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.red)

            Text(message)
                .font(TranceTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(TranceRadius.thumbnail)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if viewModel.stage == .complete, let result = viewModel.analysisResult {
                Button {
                    var updatedFile = audioFile
                    updatedFile.analysisResult = result
                    if let transcription = viewModel.transcriptionResult {
                        updatedFile.transcription = transcription.fullText
                    }
                    onAnalysisComplete(updatedFile, result)
                    dismiss()
                } label: {
                    Label(
                        "Continue to Session Generation",
                        systemImage: "arrow.right.circle.fill"
                    )
                    .font(TranceTypography.sectionTitle)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.horizontal)
            } else if viewModel.stage == .failed {
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(TranceTypography.sectionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.horizontal)
            }
        }
    }

    private func cancelAnalysis() {
        Task {
            await viewModel.cancel()
        }
    }
}

// MARK: - Analysis Stage

extension AnalysisStage {
    var title: String {
        switch self {
        case .starting:
            return "Starting..."
        case .transcribing:
            return "Transcribing Audio"
        case .analyzing:
            return "AI Analysis"
        case .generatingSession:
            return "Generating Light Session"
        case .complete:
            return "Complete"
        case .failed:
            return "Failed"
        }
    }

    var description: String {
        switch self {
        case .starting:
            return "Preparing audio analysis"
        case .transcribing:
            return "Converting speech to text"
        case .analyzing:
            return "Generating therapy recommendations"
        case .generatingSession:
            return "Creating synchronized light session"
        case .complete:
            return "Session ready to use"
        case .failed:
            return "Something went wrong"
        }
    }

    var color: Color {
        switch self {
        case .starting, .transcribing, .analyzing, .generatingSession:
            return .blue
        case .complete:
            return .green
        case .failed:
            return .red
        }
    }
}

#Preview {
    AnalysisProgressView(
        audioFile: AudioFile(
            filename: "test.m4a",
            duration: 300,
            fileSize: 1024000
        )
    ) { file, _ in
        print("Analysis complete for: \(file.filename)")
    }
}
