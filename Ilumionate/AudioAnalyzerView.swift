//
//  AudioAnalyzerView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/7/26.
//

import SwiftUI

struct AudioAnalyzerView: View {
    @Environment(\.dismiss) private var dismiss
    let audioURL: URL?
    
    @State private var isAnalyzing = true
    @State private var analysisProgress = 0.0
    
    // Customization parameters
    @State private var intensityBoost = 0.0
    @State private var useBilateral = false
    @State private var dominantFrequency = 10.0
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: TranceSpacing.cardMargin) {
                        
                        if isAnalyzing {
                            analyzingStateView
                        } else {
                            resultsStateView
                        }
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.vertical, TranceSpacing.cardMargin)
                }
            }
            .navigationTitle("Audio Analyzer")
            .navigationBarTitleDisplayMode(.large)
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
                
                ToolbarItem(placement: .primaryAction) {
                    if !isAnalyzing {
                        Button("Save") {
                            TranceHaptics.shared.light()
                            dismiss()
                        }
                        .font(TranceTypography.body)
                        .foregroundColor(.roseGold)
                    }
                }
            }
            .onAppear {
                startAnalysis()
            }
        }
    }
    
    // MARK: - States
    private var analyzingStateView: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            Spacer().frame(height: 100)
            
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.roseGold.opacity(0.3), .roseDeep.opacity(0.8), .bwTheta.opacity(0.3)],
                            center: .center
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(analysisProgress * 360))
                
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 40))
                    .foregroundColor(.roseGold)
                    .opacity(0.8 + 0.2 * sin(analysisProgress * .pi * 4))
            }
            
            VStack(spacing: TranceSpacing.small) {
                Text("Analyzing Audio...")
                    .font(TranceTypography.screenTitle)
                    .foregroundColor(.textPrimary)
                
                Text("\(Int(analysisProgress * 100))% Complete")
                    .font(TranceTypography.body)
                    .foregroundColor(.textSecondary)
            }
        }
    }
    
    private var resultsStateView: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            waveformAnalysisCard
            detectedPhasesCard
            customizeScriptCard
            
            Button(action: {
                TranceHaptics.shared.light()
                dismiss()
            }) {
                Text("Generate Session")
                    .font(TranceTypography.body)
                    .bold()
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
            .padding(.top, TranceSpacing.list)
        }
    }
    
    // MARK: - Cards
    private var waveformAnalysisCard: some View {
        GlassCard(label: "Waveform Analysis") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: 2) {
                    ForEach(0..<40, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                i < 10 ? Color.bwDelta :
                                i < 25 ? Color.bwTheta :
                                Color.bwAlpha
                            )
                            .frame(height: CGFloat.random(in: 10...60))
                            .animation(.spring(), value: analysisProgress)
                    }
                }
                .frame(height: 80)
                .frame(maxWidth: .infinity)
                
                HStack {
                    PhasePill(phase: "Induction")
                    PhasePill(phase: "Deepening")
                    PhasePill(phase: "Return")
                }
            }
        }
    }
    
    private var detectedPhasesCard: some View {
        GlassCard(label: "Detected Phases") {
            VStack(spacing: TranceSpacing.list) {
                phaseRow(title: "Induction (0:00 - 5:20)", type: "Delta Waves", frequency: "2.5 Hz", color: .bwDelta)
                Divider().background(Color.glassBorder)
                phaseRow(title: "Deep State (5:20 - 24:15)", type: "Theta Waves", frequency: "6.0 Hz", color: .bwTheta)
                Divider().background(Color.glassBorder)
                phaseRow(title: "Awakening (24:15 - 28:00)", type: "Alpha Waves", frequency: "10.0 Hz", color: .bwAlpha)
            }
        }
    }
    
    private var customizeScriptCard: some View {
        GlassCard(label: "Customize Script") {
            VStack(spacing: TranceSpacing.list) {
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    HStack {
                        Text("Intensity Boost")
                            .font(TranceTypography.body)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(Int(intensityBoost * 100))%")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Slider(value: $intensityBoost, in: -0.5...0.5)
                        .tint(.roseGold)
                }
                
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    HStack {
                        Text("Target Frequency")
                            .font(TranceTypography.body)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(dominantFrequency, specifier: "%.1f") Hz")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Slider(value: $dominantFrequency, in: 0.5...40.0)
                        .tint(.bwTheta)
                }
                
                Toggle("Enable Bilateral Stimulation", isOn: $useBilateral)
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)
                    .tint(.roseDeep)
            }
        }
    }
    
    // MARK: - Helpers
    private func phaseRow(title: String, type: String, frequency: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)
                Text(type)
                    .font(TranceTypography.caption)
                    .foregroundColor(color)
            }
            Spacer()
            Text(frequency)
                .font(TranceTypography.body)
                .bold()
                .foregroundColor(.textSecondary)
        }
    }
    
    private func startAnalysis() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            withAnimation(.linear(duration: 0.05)) {
                analysisProgress += 0.02
                if analysisProgress >= 1.0 {
                    timer.invalidate()
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        isAnalyzing = false
                    }
                }
            }
        }
    }
}


#Preview {
    AudioAnalyzerView(audioURL: nil)
}
