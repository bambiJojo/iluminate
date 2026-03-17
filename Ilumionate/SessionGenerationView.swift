//
//  SessionGenerationView.swift
//  Ilumionate
//
//  Redesigned Session Generation View for Trance UI
//

import SwiftUI

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
            ZStack {
                Color.bgPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: TranceSpacing.cardMargin) {
                        heroSection
                        analysisSummarySection
                        
                        if let hypnosis = analysis.hypnosisMetadata {
                            hypnosisDetailsSection(hypnosis)
                        }
                        
                        customizationSection
                        
                        // Play Button
                        Button {
                            TranceHaptics.shared.medium()
                            showingPlayer = true
                        } label: {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 24))
                                Text("Begin Therapy Session")
                                    .font(TranceTypography.body)
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.roseGold, .roseDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(generatedSession == nil)
                        .opacity(generatedSession == nil ? 0.6 : 1.0)
                        
                        Spacer(minLength: TranceSpacing.screen)
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.vertical, TranceSpacing.cardMargin)
                }
            }
            .navigationTitle("Session Designer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .onAppear {
                generateSession()
            }
            .fullScreenCover(isPresented: $showingPlayer) {
                if let session = generatedSession {
                    UnifiedPlayerView(
                        mode: .session(session: session, audioFile: audioFile),
                        engine: engine
                    )
                }
            }
        }
    }
    
    // MARK: - Sections
    
    private var heroSection: some View {
        VStack(spacing: TranceSpacing.list) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [contentTypeColor.opacity(0.8), contentTypeColor.opacity(0.2), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: contentTypeIcon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: TranceSpacing.micro) {
                Text(audioFile.filename.replacingOccurrences(of: ".m4a", with: "").replacingOccurrences(of: ".mp3", with: ""))
                    .font(TranceTypography.screenTitle)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: TranceSpacing.list) {
                    Label(audioFile.durationFormatted, systemImage: "clock")
                        .font(TranceTypography.caption)
                        .foregroundColor(.textSecondary)
                    
                    PhasePill(phase: analysis.contentType.rawValue.capitalized)
                }
            }
        }
        .padding(.vertical, TranceSpacing.cardMargin)
    }
    
    private var analysisSummarySection: some View {
        GlassCard(label: "AI Analysis") {
            VStack(spacing: TranceSpacing.list) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: TranceSpacing.list) {
                    infoBox(icon: "brain", label: "Mood", value: analysis.mood.rawValue.capitalized, color: .bwTheta)
                    infoBox(icon: "bolt.fill", label: "Energy", value: "\(Int(analysis.energyLevel * 100))%", color: .roseGold)
                    infoBox(icon: "waveform", label: "Frequency", value: "\(Int(analysis.suggestedFrequencyRange.lowerBound))-\(Int(analysis.suggestedFrequencyRange.upperBound)) Hz", color: .bwAlpha)
                    infoBox(icon: "light.max", label: "Intensity", value: "\(Int(analysis.suggestedIntensity * 100))%", color: .roseDeep)
                }
                
                if !analysis.aiSummary.isEmpty {
                    Divider().background(Color.glassBorder)
                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Label("AI Insights", systemImage: "sparkles")
                            .font(TranceTypography.body)
                            .foregroundColor(.textPrimary)
                        Text(analysis.aiSummary)
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
    }
    
    private func hypnosisDetailsSection(_ hypnosis: HypnosisMetadata) -> some View {
        GlassCard(label: "Hypnosis Details") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Text("Detected Phases (\(hypnosis.phases.count))")
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)
                
                VStack(spacing: TranceSpacing.micro) {
                    ForEach(hypnosis.phases.prefix(5)) { phase in
                        HStack {
                            Circle()
                                .fill(colorForPhase(phase.phase))
                                .frame(width: 8, height: 8)
                            Text(phase.phase.displayName)
                                .font(TranceTypography.caption)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Text("\(formatTime(phase.startTime)) - \(formatTime(phase.endTime))")
                                .font(TranceTypography.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                
                if let induction = hypnosis.inductionStyle {
                    HStack {
                        Text("Induction")
                            .font(TranceTypography.body)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        PhasePill(phase: induction.rawValue.capitalized)
                    }
                }
                
                HStack {
                    Text("Depth")
                        .font(TranceTypography.body)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    PhasePill(phase: hypnosis.estimatedTranceDeph.rawValue.capitalized)
                }
            }
        }
    }
    
    private var customizationSection: some View {
        GlassCard(label: "Session Customization") {
            VStack(spacing: TranceSpacing.list) {
                // Intensity
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    HStack {
                        Text("Overall Intensity")
                            .font(TranceTypography.body)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(Int(config.intensityMultiplier * 100))%")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Slider(value: $config.intensityMultiplier, in: 0.5...1.5)
                        .tint(.roseGold)
                        .onChange(of: config.intensityMultiplier) { _, _ in
                            regenerateSession()
                        }
                }
                
                // Transition Smoothness
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    HStack {
                        Text("Transition Smoothness")
                            .font(TranceTypography.body)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(smoothnessLabel)
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Slider(value: $config.transitionSmoothness, in: 0.0...1.0)
                        .tint(.bwTheta)
                        .onChange(of: config.transitionSmoothness) { _, _ in
                            regenerateSession()
                        }
                }
                
                // Bilateral Mode
                Toggle("Bilateral Stimulation", isOn: $config.bilateralMode)
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)
                    .tint(.roseDeep)
                    .onChange(of: config.bilateralMode) { _, _ in
                        regenerateSession()
                    }
            }
        }
    }
    
    // MARK: - Logic
    
    private func generateSession() {
        generatedSession = generator.generateSession(
            from: audioFile,
            analysis: analysis,
            config: config
        )
    }
    
    private func regenerateSession() {
        TranceHaptics.shared.selection()
        generateSession()
    }
    
    // MARK: - Helpers
    
    private func infoBox(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: TranceSpacing.micro) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(label)
                .font(TranceTypography.caption)
                .foregroundColor(.textSecondary)
            Text(value)
                .font(TranceTypography.body)
                .foregroundColor(.textPrimary)
                .bold()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TranceSpacing.inner)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: TranceRadius.thumbnail))
    }
    
    private var smoothnessLabel: String {
        if config.transitionSmoothness < 0.3 { return "Sharp" }
        if config.transitionSmoothness < 0.7 { return "Moderate" }
        return "Smooth"
    }

    private var contentTypeIcon: String {
        switch analysis.contentType {
        case .hypnosis: return "brain"
        case .meditation: return "figure.mind.and.body"
        case .music: return "music.note"
        case .guidedImagery: return "eye"
        case .affirmations: return "quote.bubble"
        case .unknown: return "waveform"
        }
    }

    private var contentTypeColor: Color {
        switch analysis.contentType {
        case .hypnosis: return .bwTheta
        case .meditation: return .bwAlpha
        case .music: return .roseGold
        case .guidedImagery: return .roseDeep
        case .affirmations: return .bwBeta
        case .unknown: return .textSecondary
        }
    }
    
    private func colorForPhase(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .preTalk: return .textSecondary
        case .induction: return .bwAlpha
        case .deepening: return .bwTheta
        case .therapy, .suggestions: return .roseGold
        case .conditioning: return .roseDeep
        case .emergence: return .bwBeta
        case .transitional: return .textLight
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
