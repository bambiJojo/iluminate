//
//  SessionGenerationView.swift
//  Ilumionate
//
//  Created by AI Assistant on 2/24/26.
//

import SwiftUI

/// Preview and customize AI-generated light therapy session
struct SessionGenerationView: View {

    let audioFile: AudioFile
    let analysis: AnalysisResult
    @Bindable var engine: LightEngine

    @State private var generator = SessionGenerator()
    @State private var generatedSession: LightSession?
    @State private var config = SessionGenerator.GenerationConfig.default
    @State private var showingPlayer = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Header
                    headerSection

                    // Analysis Summary
                    analysisSummary

                    // Hypnosis-specific details (if applicable)
                    if let hypnosis = analysis.hypnosisMetadata {
                        hypnosisDetails(hypnosis)
                    }

                    // Customization controls
                    customizationSection

                    // Play button
                    playButton
                }
                .padding()
            }
            .navigationTitle("Generated Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                generateSession()
            }
            .fullScreenCover(isPresented: $showingPlayer) {
                if let session = generatedSession {
                    SessionPlayerView(
                        session: session,
                        audioFile: audioFile,
                        engine: engine
                    )
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 0) {
            // Large icon area with gradient (like SessionCardView)
            ZStack {
                // Background gradient based on content type
                contentTypeGradient
                    .ignoresSafeArea()

                // Large icon
                Image(systemName: contentTypeIcon)
                    .font(.system(size: 70))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            }
            .frame(height: 160)

            // Info area
            VStack(spacing: 12) {
                Text(audioFile.filename.replacingOccurrences(of: ".m4a", with: "").replacingOccurrences(of: ".mp3", with: ""))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                HStack(spacing: 16) {
                    Label(audioFile.durationFormatted, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Content type badge
                    Text(analysis.contentType.rawValue.capitalized)
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(contentTypeColor.opacity(0.2))
                        .foregroundStyle(contentTypeColor)
                        .cornerRadius(8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Analysis Summary

    private var analysisSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("AI Analysis", systemImage: "brain.head.profile")
                .font(.headline)

            VStack(spacing: 12) {
                infoRow(icon: "brain", label: "Mood", value: analysis.mood.rawValue.capitalized)
                infoRow(icon: "bolt.fill", label: "Energy Level", value: "\(Int(analysis.energyLevel * 100))%")
                infoRow(icon: "waveform", label: "Frequency Range", value: "\(Int(analysis.suggestedFrequencyRange.lowerBound))-\(Int(analysis.suggestedFrequencyRange.upperBound)) Hz")
                infoRow(icon: "light.max", label: "Intensity", value: "\(Int(analysis.suggestedIntensity * 100))%")

                if let temp = analysis.suggestedColorTemperature {
                    infoRow(icon: "thermometer.medium", label: "Color Temperature", value: "\(Int(temp))K")
                }
            }

            // AI Summary
            if !analysis.aiSummary.isEmpty {
                Divider()

                Text(analysis.aiSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Hypnosis Details

    private func hypnosisDetails(_ hypnosis: HypnosisMetadata) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Hypnosis Session Analysis", systemImage: "brain")
                .font(.headline)

            // Phases
            VStack(alignment: .leading, spacing: 8) {
                Text("Detected Phases: \(hypnosis.phases.count)")
                    .font(.subheadline.bold())

                ForEach(hypnosis.phases.prefix(5)) { phase in
                    HStack {
                        Circle()
                            .fill(colorForPhase(phase.phase))
                            .frame(width: 8, height: 8)

                        Text(phase.phase.displayName)
                            .font(.caption)

                        Spacer()

                        Text("\(formatTime(phase.startTime)) - \(formatTime(phase.endTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Induction style & trance depth
            if let inductionStyle = hypnosis.inductionStyle {
                infoRow(icon: "arrow.down.circle", label: "Induction", value: inductionStyle.rawValue.capitalized)
            }

            infoRow(icon: "gauge.high", label: "Trance Depth", value: hypnosis.estimatedTranceDeph.rawValue.capitalized)

            // Techniques
            if !hypnosis.detectedTechniques.isEmpty {
                Text("Techniques: \(hypnosis.detectedTechniques.count) detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Customization Section

    private var customizationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Customization", systemImage: "slider.horizontal.3")
                .font(.headline)

            // Intensity multiplier
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Overall Intensity")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(config.intensityMultiplier * 100))%")
                        .font(.subheadline.bold())
                }

                Slider(value: $config.intensityMultiplier, in: 0.5...1.5)
                    .onChange(of: config.intensityMultiplier) { _, _ in
                        regenerateSession()
                    }
            }

            // Transition smoothness
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transition Smoothness")
                        .font(.subheadline)
                    Spacer()
                    Text(smoothnessLabel)
                        .font(.subheadline.bold())
                }

                Slider(value: $config.transitionSmoothness, in: 0.0...1.0)
                    .onChange(of: config.transitionSmoothness) { _, _ in
                        regenerateSession()
                    }
            }

            // Bilateral mode toggle
            Toggle(isOn: $config.bilateralMode) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bilateral Mode")
                        .font(.subheadline)
                    Text("Alternating left/right stimulation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: config.bilateralMode) { _, _ in
                regenerateSession()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Play Button

    private var playButton: some View {
        Button {
            showingPlayer = true
        } label: {
            Label("Play Session with Audio", systemImage: "play.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(12)
        }
        .disabled(generatedSession == nil)
    }

    // MARK: - Helper Views

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.bold())
        }
    }

    // MARK: - Logic

    private func generateSession() {
        print("🎨 Generating session...")
        generatedSession = generator.generateSession(
            from: audioFile,
            analysis: analysis,
            config: config
        )
        print("✅ Session generated with \(generatedSession?.light_score.count ?? 0) moments")
    }

    private func regenerateSession() {
        generateSession()
    }

    // MARK: - Helpers

    private var contentTypeIcon: String {
        switch analysis.contentType {
        case .hypnosis:
            return "brain"
        case .meditation:
            return "figure.mind.and.body"
        case .music:
            return "music.note"
        case .guidedImagery:
            return "eye"
        case .affirmations:
            return "quote.bubble"
        case .unknown:
            return "waveform"
        }
    }

    private var contentTypeColor: Color {
        switch analysis.contentType {
        case .hypnosis:
            return .purple
        case .meditation:
            return .blue
        case .music:
            return .pink
        case .guidedImagery:
            return .green
        case .affirmations:
            return .orange
        case .unknown:
            return .gray
        }
    }

    private var contentTypeGradient: LinearGradient {
        switch analysis.contentType {
        case .hypnosis:
            // Deep purple and indigo for hypnosis
            return LinearGradient(
                colors: [Color(red: 0.4, green: 0.2, blue: 0.6), Color(red: 0.3, green: 0.1, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .meditation:
            // Calming blues for meditation
            return LinearGradient(
                colors: [Color(red: 0.2, green: 0.4, blue: 0.7), Color(red: 0.1, green: 0.3, blue: 0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .music:
            // Vibrant pink/magenta for music
            return LinearGradient(
                colors: [Color(red: 0.8, green: 0.2, blue: 0.6), Color(red: 0.6, green: 0.1, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .guidedImagery:
            // Fresh greens for guided imagery
            return LinearGradient(
                colors: [Color(red: 0.2, green: 0.6, blue: 0.4), Color(red: 0.1, green: 0.5, blue: 0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .affirmations:
            // Warm orange for affirmations
            return LinearGradient(
                colors: [Color(red: 0.9, green: 0.5, blue: 0.2), Color(red: 0.8, green: 0.4, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .unknown:
            // Neutral grays for unknown
            return LinearGradient(
                colors: [Color(red: 0.4, green: 0.4, blue: 0.4), Color(red: 0.3, green: 0.3, blue: 0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func colorForPhase(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .preTalk:
            return .gray
        case .induction:
            return .blue
        case .deepening:
            return .purple
        case .therapy, .suggestions:
            return .green
        case .conditioning:
            return .orange
        case .emergence:
            return .yellow
        case .transitional:
            return .teal
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var smoothnessLabel: String {
        if config.transitionSmoothness < 0.3 {
            return "Sharp"
        } else if config.transitionSmoothness < 0.7 {
            return "Moderate"
        } else {
            return "Smooth"
        }
    }
}

#Preview {
    SessionGenerationView(
        audioFile: AudioFile(
            filename: "Deep Trance.m4a",
            url: URL(fileURLWithPath: "/tmp/test.m4a"),
            duration: 1200,
            fileSize: 5000000
        ),
        analysis: AnalysisResult(
            mood: .meditative,
            energyLevel: 0.3,
            suggestedFrequencyRange: 4.0...8.0,
            suggestedIntensity: 0.6,
            suggestedColorTemperature: 2500,
            keyMoments: [],
            aiSummary: "This is a progressive relaxation induction leading into deep therapeutic work.",
            recommendedPreset: "Deep Hypnosis",
            contentType: .hypnosis
        ),
        engine: LightEngine()
    )
}
