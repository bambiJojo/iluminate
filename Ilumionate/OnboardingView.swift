//
//  OnboardingView.swift
//  Ilumionate
//
//  Created by Claude on 3/5/26.
//

import SwiftUI

/// Focused onboarding flow for hypnosis audio player + mind machine
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var animateElements = false
    @State private var showWelcomeSession = false
    @State private var hasCompletedIntroSession = false
    @State private var lightEngine = LightEngine()

    let totalSteps = 5

    var body: some View {
        ZStack {
            // Dynamic background that changes with steps
            backgroundForStep(currentStep)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.0), value: currentStep)

            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator

                Spacer()

                // Step content
                stepContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                Spacer()

                // Navigation buttons
                navigationButtons
                    .padding(.bottom, TranceSpacing.cardMargin)
            }
        }
        .onAppear {
            animateElements = true
        }
        .fullScreenCover(isPresented: $showWelcomeSession) {
            if let welcomeSession = loadWelcomeSession() {
                SessionPlayerView(
                    session: welcomeSession,
                    engine: lightEngine
                )
                .onDisappear {
                    hasCompletedIntroSession = true
                    withAnimation(.easeInOut(duration: 0.8)) {
                        currentStep = 4 // Move to final step
                    }
                }
            }
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        VStack(spacing: TranceSpacing.card) {
            HStack(spacing: TranceSpacing.list) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? Color.bwTheta : Color.roseGold)
                        .frame(width: step == currentStep ? 12 : 8, height: step == currentStep ? 12 : 8)
                        .scaleEffect(step == currentStep && animateElements ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }

            Text("Step \(currentStep + 1) of \(totalSteps)")
                .font(TranceTypography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, TranceSpacing.screen)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch currentStep {
            case 0:
                welcomeStep
            case 1:
                hypnosisPlayerStep
            case 2:
                mindMachineStep
            case 3:
                positioningInstructionsStep
            case 4:
                completedStep
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, TranceSpacing.cardMargin)
    }

    // MARK: - Step Views

    private var welcomeStep: some View {
        VStack(spacing: TranceSpacing.screen) {
            // Hero icon with dual symbols
            HStack(spacing: TranceSpacing.cardMargin) {
                // Hypnosis/Audio symbol
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.bwGamma.opacity(0.3),
                                    Color.roseDeep.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 15,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: "waveform")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.bwGamma)
                }
                .scaleEffect(animateElements ? 1.0 : 0.8)
                .opacity(animateElements ? 1.0 : 0.0)
                .animation(.spring(response: 0.8, dampingFraction: 0.6), value: animateElements)

                // Mind Machine/Light symbol
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.lavender.opacity(0.3),
                                    Color.warmAccent.opacity(0.1),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 15,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.lavender)
                }
                .scaleEffect(animateElements ? 1.0 : 0.8)
                .opacity(animateElements ? 1.0 : 0.0)
                .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2), value: animateElements)
            }

            VStack(spacing: TranceSpacing.card) {
                Text("Welcome to Ilumionate")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("Your personal hypnosis audio player and mind machine for deep relaxation and transformation")
                    .font(TranceTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            .opacity(animateElements ? 1.0 : 0.0)
            .offset(y: animateElements ? 0 : 20)
            .animation(.easeOut(duration: 0.8).delay(0.5), value: animateElements)
        }
    }

    private var hypnosisPlayerStep: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            // Animated audio waveform
            VStack(spacing: TranceSpacing.card) {
                HStack(spacing: TranceSpacing.list) {
                    ForEach(0..<8, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.bwGamma.opacity(0.8))
                            .frame(width: 6, height: CGFloat([25, 45, 35, 55, 40, 60, 30, 20][index]))
                            .scaleEffect(y: animateElements ? 1.0 : 0.3)
                            .animation(
                                .easeInOut(duration: 1.2)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                                value: animateElements
                            )
                    }
                }

                Image(systemName: "headphones")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.roseDeep)
            }

            VStack(spacing: TranceSpacing.card) {
                Text("Hypnosis Audio Player")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                VStack(spacing: TranceSpacing.list) {
                    featurePoint(
                        icon: "square.and.arrow.down",
                        title: "Import Your Files",
                        description: "Add your own hypnosis sessions, meditations, and audio files"
                    )

                    featurePoint(
                        icon: "music.note.list",
                        title: "Create Playlists",
                        description: "Organize your sessions into collections for different goals"
                    )

                    featurePoint(
                        icon: "play.circle.fill",
                        title: "Seamless Playback",
                        description: "High-quality audio playback with progress tracking"
                    )
                }
            }
        }
    }

    private var mindMachineStep: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            // Interactive light demonstration
            VStack(spacing: TranceSpacing.card) {
                ZStack {
                    Circle()
                        .stroke(Color.lavender.opacity(0.3), lineWidth: 2)
                        .frame(width: 120, height: 120)

                    Circle()
                        .fill(Color.warmAccent)
                        .frame(width: 80, height: 80)
                        .opacity(animateElements ? 0.8 : 0.2)
                        .scaleEffect(animateElements ? 1.0 : 0.6)
                        .animation(
                            .easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                            value: animateElements
                        )

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white)
                }

                Text("Light Synchronization")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: TranceSpacing.card) {
                Text("Mind Machine")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                VStack(spacing: TranceSpacing.list) {
                    featurePoint(
                        icon: "lightbulb.fill",
                        title: "Built-in Sessions",
                        description: "Pre-designed light therapy sessions for relaxation and focus"
                    )

                    featurePoint(
                        icon: "waveform.path",
                        title: "Audio Sync",
                        description: "Synchronize pulsing lights with your hypnosis audio files"
                    )

                    featurePoint(
                        icon: "brain.head.profile",
                        title: "Brainwave Entrainment",
                        description: "Gentle light patterns guide your mind into desired states"
                    )
                }
            }
        }
    }

    private var positioningInstructionsStep: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            // Visual demonstration of phone positioning
            VStack(spacing: TranceSpacing.card) {
                // Phone positioning diagram
                ZStack {
                    // Face outline
                    Ellipse()
                        .stroke(Color.lavender.opacity(0.3), lineWidth: 2)
                        .frame(width: 100, height: 130)

                    // Closed eyes
                    HStack(spacing: 20) {
                        // Left eye
                        Capsule()
                            .fill(Color.roseDeep.opacity(0.6))
                            .frame(width: 16, height: 4)

                        // Right eye
                        Capsule()
                            .fill(Color.roseDeep.opacity(0.6))
                            .frame(width: 16, height: 4)
                    }
                    .offset(y: -20)

                    // Phone above face
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.warmAccent.opacity(0.8))
                        .frame(width: 60, height: 120)
                        .offset(y: -90)
                        .scaleEffect(animateElements ? 1.0 : 0.8)
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateElements)

                    // Light rays emanating from phone
                    ForEach(0..<5, id: \.self) { index in
                        Rectangle()
                            .fill(Color.bwAlpha.opacity(0.4))
                            .frame(width: 2, height: 30)
                            .offset(y: -60)
                            .rotationEffect(.degrees(Double(index - 2) * 15))
                            .opacity(animateElements ? 0.8 : 0.2)
                            .animation(
                                .easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.1),
                                value: animateElements
                            )
                    }
                }
                .frame(height: 200)

                Text("Position & Close Eyes")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: TranceSpacing.card) {
                Text("How to Use the Light Machine")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                VStack(spacing: TranceSpacing.list) {
                    positioningStep(
                        number: 1,
                        icon: "iphone.gen3",
                        title: "Position Your Phone",
                        description: "Hold your phone 6-12 inches directly above your face, screen facing down"
                    )

                    positioningStep(
                        number: 2,
                        icon: "eye.slash.fill",
                        title: "Close Your Eyes",
                        description: "Gently close your eyes and let the light penetrate through your eyelids"
                    )

                    positioningStep(
                        number: 3,
                        icon: "brain.head.profile",
                        title: "Allow Deep Trance",
                        description: "Let the pulsing light gently massage your mind and guide you into deep relaxation"
                    )
                }
            }
        }
    }

    private var prepareForSessionStep: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.green)

            VStack(spacing: TranceSpacing.card) {
                Text("Prepare for Your First Session")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                VStack(spacing: TranceSpacing.list) {
                    preparationTip(
                        icon: "moon.stars.fill",
                        text: "Find a quiet, comfortable space"
                    )

                    preparationTip(
                        icon: "eye.fill",
                        text: "Sit upright with a relaxed posture"
                    )

                    preparationTip(
                        icon: "speaker.wave.2.fill",
                        text: "Optional: Use headphones for audio sessions"
                    )

                    preparationTip(
                        icon: "clock.fill",
                        text: "Allow 3 minutes for your introduction"
                    )
                }
            }
        }
    }

    private var introSessionStep: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            // Pulsing session preview
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.lavender.opacity(0.6),
                                Color.roseDeep.opacity(0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 100
                        )
                    )
                    .frame(width: 180, height: 180)

                VStack(spacing: TranceSpacing.list) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.primary)

                    Text("3 min")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(.primary)
                }
            }

            VStack(spacing: TranceSpacing.card) {
                Text("Ready for Your Introduction?")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("Experience a gentle 3-minute session designed to introduce you to the fundamentals of light therapy")
                    .font(TranceTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    TranceHaptics.shared.light()
                    showWelcomeSession = true
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Image(systemName: "play.fill")
                        Text("Start Introduction Session")
                    }
                    .font(TranceTypography.body)
                    .foregroundStyle(.white)
                    .padding(TranceSpacing.card)
                    .background(
                        RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                            .fill(Color.bwTheta)
                            .shadow(
                                color: Color.bwTheta.opacity(0.3),
                                radius: 12,
                                x: 0,
                                y: 6
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var completedStep: some View {
        VStack(spacing: TranceSpacing.screen) {
            // Success animation
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.green.opacity(0.3),
                                Color.bwAlpha.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.green)
            }
            .scaleEffect(animateElements ? 1.0 : 0.8)
            .opacity(animateElements ? 1.0 : 0.0)
            .animation(.spring(response: 0.8, dampingFraction: 0.6), value: animateElements)

            VStack(spacing: TranceSpacing.card) {
                Text("You're Ready to Begin!")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("Your personal hypnosis and light therapy experience awaits. Import your audio files and start your journey to deeper relaxation and transformation.")
                    .font(TranceTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)

                VStack(spacing: TranceSpacing.list) {
                    nextStepPoint(
                        icon: "waveform.circle.fill",
                        text: "Import your hypnosis audio files"
                    )

                    nextStepPoint(
                        icon: "lightbulb.circle.fill",
                        text: "Try built-in mind machine sessions"
                    )

                    nextStepPoint(
                        icon: "music.note.list",
                        text: "Create personalized playlists"
                    )
                }
            }
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    TranceHaptics.shared.light()
                    withAnimation(.easeInOut(duration: 0.5)) {
                        currentStep -= 1
                    }
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Image(systemName: "chevron.left")
                        Text("Previous")
                    }
                    .font(TranceTypography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TranceSpacing.cardMargin)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                            .fill(Color.roseGold.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button {
                    TranceHaptics.shared.light()
                    withAnimation(.easeInOut(duration: 0.5)) {
                        currentStep += 1
                        animateElements = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            animateElements = true
                        }
                    }
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Text(currentStep == 3 ? "Let's Begin" : "Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(TranceTypography.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, TranceSpacing.cardMargin)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                            .fill(Color.bwTheta)
                            .shadow(
                                color: Color.bwTheta.opacity(0.3),
                                radius: 8,
                                x: 0,
                                y: 4
                            )
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    TranceHaptics.shared.medium()
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    dismiss()
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Text("Start Using Ilumionate")
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .font(TranceTypography.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, TranceSpacing.cardMargin)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                            .fill(Color.green)
                            .shadow(
                                color: Color.green.opacity(0.3),
                                radius: 12,
                                x: 0,
                                y: 6
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TranceSpacing.cardMargin)
    }

    // MARK: - Background Views

    @ViewBuilder
    private func backgroundForStep(_ step: Int) -> some View {
        switch step {
        case 0:
            // Welcome - soft gradient
            LinearGradient(
                colors: [
                    Color.white,
                    Color.roseGold.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 1, 2:
            // Learning - gentle animation
            Color.bgPrimary
        case 3:
            // Positioning instructions - focused
            LinearGradient(
                colors: [
                    Color.warmAccent.opacity(0.1),
                    Color.lavender.opacity(0.1),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case 4:
            // Completion - success
            LinearGradient(
                colors: [
                    Color.green.opacity(0.1),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            Color.clear
        }
    }

    // MARK: - Helper Views

    private func positioningStep(number: Int, icon: String, title: String, description: String) -> some View {
        HStack(spacing: TranceSpacing.card) {
            // Step number with icon
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.warmAccent.opacity(0.3))
                        .frame(width: 40, height: 40)

                    Text("\(number)")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.warmAccent)
                }

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.lavender)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(TranceTypography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
        .padding(.horizontal, TranceSpacing.list)
    }

    private func featurePoint(icon: String, title: String, description: String) -> some View {
        HStack(spacing: TranceSpacing.card) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.bwTheta)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(TranceTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(TranceSpacing.list)
        .background(
            RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                .fill(Color.white.opacity(0.8))
        )
    }

    private func workflowStep(number: Int, text: String) -> some View {
        HStack(spacing: TranceSpacing.card) {
            ZStack {
                Circle()
                    .fill(Color.bwTheta.opacity(0.2))
                    .frame(width: 32, height: 32)

                Text("\(number)")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.bwTheta)
            }

            Text(text)
                .font(TranceTypography.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(TranceSpacing.list)
    }

    private func preparationTip(icon: String, text: String) -> some View {
        HStack(spacing: TranceSpacing.card) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.bwAlpha)
                .frame(width: 24)

            Text(text)
                .font(TranceTypography.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(TranceSpacing.list)
        .background(
            RoundedRectangle(cornerRadius: TranceRadius.button)
                .fill(Color.bwAlpha.opacity(0.1))
        )
    }

    private func nextStepPoint(icon: String, text: String) -> some View {
        HStack(spacing: TranceSpacing.card) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.green)
                .frame(width: 24)

            Text(text)
                .font(TranceTypography.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(TranceSpacing.list)
        .background(
            RoundedRectangle(cornerRadius: TranceRadius.button)
                .fill(Color.green.opacity(0.1))
        )
    }

    // MARK: - Helper Methods

    private func loadWelcomeSession() -> LightSession? {
        return try? LightScoreReader.loadSession(named: "welcome_introduction")
    }
}

#Preview {
    OnboardingView()
}