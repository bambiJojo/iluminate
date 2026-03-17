//
//  OnboardingView.swift
//  LumeSync
//
//  Created by Claude on 3/5/26.
//

import SwiftUI

/// Focused onboarding flow for hypnosis audio player + mind machine
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Geometry Effect namespace for smooth transitions
    @Namespace private var animation
    
    // State to track the current phase of onboarding
    @State private var currentPhase: OnboardingPhase = .welcome
    
    // User selections
    @State private var selectedGoal: OnboardingGoal? = nil
    
    // Animation flags for entry/exit
    @State private var isAnimating: Bool = false
    @State private var showWelcomeSession = false
    @State private var lightEngine = LightEngine()
    
    // Complex Animation Properties (from reference design style)
    @State private var characterOffset: CGFloat = 0
    @State private var bgOffset: CGFloat = .zero
    @State private var textOffset: CGFloat = .zero
    
    // Phases of the onboarding flow
    enum OnboardingPhase: Int, CaseIterable {
        case welcome = 0
        case questionnaire
        case personalizedResponse
        case warning
        case completed
    }
    
    var body: some View {
        ZStack {
            // Background
            backgroundForPhase(currentPhase)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: currentPhase)
            
            VStack {
                // Header (Progress or Welcome)
                if currentPhase != .welcome && currentPhase != .completed {
                    progressIndicator()
                        .padding(.top, 20)
                }
                
                Spacer()
                
                // Main Content
                Group {
                    switch currentPhase {
                    case .welcome:
                        welcomePhase
                            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                    case .questionnaire:
                        questionnairePhase
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    case .personalizedResponse:
                        personalizedResponsePhase
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    case .warning:
                        warningPhase
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    case .completed:
                        completedPhase
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }
                }
                
                Spacer()
                
                // Footer (Navigation)
                navigationFooter
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                isAnimating = true
                characterOffset = -20
            }
        }
        .fullScreenCover(isPresented: $showWelcomeSession) {
            if let welcomeSession = loadWelcomeSession() {
                UnifiedPlayerView(
                    mode: .session(session: welcomeSession, audioFile: nil),
                    engine: lightEngine
                )
                .onDisappear {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        currentPhase = .completed
                    }
                }
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .onAppear {
            AppDelegate.orientationLock = UIInterfaceOrientationMask.portrait
        }
        .onDisappear {
            AppDelegate.orientationLock = UIInterfaceOrientationMask.all
        }
    }
    
    // MARK: - Navigation Footer
    private var navigationFooter: some View {
        HStack {
            // Back Button
            if currentPhase != .welcome && currentPhase != .completed {
                Button(action: previousPhase) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            
            Spacer()
            
            // Next / Continue Button
            Button(action: nextPhase) {
                HStack {
                    Text(buttonTextForPhase(currentPhase))
                        .font(TranceTypography.body)
                        .fontWeight(.semibold)
                    
                    if currentPhase != .questionnaire {
                        Image(systemName: "arrow.right")
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, (currentPhase == .questionnaire && selectedGoal == nil) ? 0 : 20)
                .frame(width: (currentPhase == .questionnaire && selectedGoal == nil) ? 50 : nil, height: 50)
                .background(Color.bwTheta)
                .clipShape(Capsule())
                .shadow(color: Color.bwTheta.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .disabled(currentPhase == .questionnaire && selectedGoal == nil)
            .opacity((currentPhase == .questionnaire && selectedGoal == nil) ? 0.5 : 1)
            .animation(.easeInOut, value: selectedGoal)
        }
    }
    
    // MARK: - Phases
    
    // 1. Welcome Phase
    private var welcomePhase: some View {
        VStack(spacing: 30) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.bwGamma.opacity(0.4), Color.clear],
                            center: .center, startRadius: 20, endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .scaleEffect(isAnimating ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 80, weight: .light))
                    .foregroundColor(Color.warmAccent)
                    .offset(y: characterOffset)
                    .animation(.spring(response: 0.6, dampingFraction: 0.5).repeatForever(autoreverses: true), value: characterOffset)
                    .onAppear {
                        characterOffset = 10
                    }
            }
            .frame(height: 350)
            
            VStack(spacing: 16) {
                Text("Welcome to LumeSync")
                    .font(TranceTypography.screenTitle)
                    .foregroundColor(.primary)
                
                Text("Your personal hypnosis audio player and mind machine for deep relaxation and transformation.")
                    .font(TranceTypography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }
    
    // 2. Questionnaire Phase
    private var questionnairePhase: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Text("What brings you here?")
                    .font(TranceTypography.screenTitle)
                
                Text("Help us tailor your mind machine experience.")
                    .font(TranceTypography.body)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
            
            VStack(spacing: 16) {
                ForEach(OnboardingGoal.allCases) { goal in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedGoal = goal
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: goal.icon)
                                .font(.title2)
                                .foregroundColor(selectedGoal == goal ? .white : .bwTheta)
                                .frame(width: 30)
                            
                            Text(goal.rawValue)
                                .font(TranceTypography.body)
                                .foregroundColor(selectedGoal == goal ? .white : .primary)
                            
                            Spacer()
                            
                            if selectedGoal == goal {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                                    .matchedGeometryEffect(id: "check", in: animation)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedGoal == goal ? Color.bwTheta : Color.white.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selectedGoal == goal ? Color.clear : Color.bwAlpha.opacity(0.3), lineWidth: 1)
                        )
                        .scaleEffect(selectedGoal == goal ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // 3. Personalized Response Phase
    private var personalizedResponsePhase: some View {
        VStack(spacing: 40) {
            if let goal = selectedGoal {
                // Animated Icon specific to goal
                ZStack {
                    Circle()
                        .fill(Color.bwTheta.opacity(0.2))
                        .frame(width: 140, height: 140)
                    
                    Image(systemName: goal.icon)
                        .font(.system(size: 60))
                        .foregroundColor(.bwTheta)
                        .scaleEffect(isAnimating ? 1.1 : 0.9)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
                }
                .padding(.top, 40)
                
                VStack(spacing: 20) {
                    Text(goal.personalizedResponseTitle)
                        .font(TranceTypography.screenTitle)
                        .multilineTextAlignment(.center)
                    
                    Text(goal.personalizedResponseDescription)
                        .font(TranceTypography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 10)
            }
        }
    }
    
    // 4. Warning Phase
    private var warningPhase: some View {
        VStack(spacing: 30) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundColor(.roseDeep)
                .shadow(color: .roseDeep.opacity(0.5), radius: 10, x: 0, y: 5)
                .padding(.top, 20)
            
            VStack(spacing: 16) {
                Text("Important Warning")
                    .font(TranceTypography.screenTitle)
                    .foregroundColor(.roseDeep)
                
                Text("This app uses flashing lights and visual patterns as part of the brainwave entrainment process.")
                    .font(TranceTypography.body.bold())
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 12) {
                    warningBullet("Do NOT use this app if you have a history of epilepsy or seizures.")
                    warningBullet("Close your eyes during light sessions. The light will penetrate your eyelids.")
                    warningBullet("Hold the screen 6-12 inches from your face.")
                }
                .padding(.top, 10)
                .padding(.horizontal, 10)
            }
        }
    }
    
    // 5. Completed Phase
    private var completedPhase: some View {
        VStack(spacing: 40) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.green.opacity(0.4), Color.clear],
                            center: .center, startRadius: 20, endRadius: 150
                        )
                    )
                    .frame(width: 200, height: 200)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 16) {
                Text("You're ready.")
                    .font(TranceTypography.screenTitle)
                
                Text("Your LumeSync journey begins now. Find a quiet space, upload an audio file, and let the mind machine guide you.")
                    .font(TranceTypography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func backgroundForPhase(_ phase: OnboardingPhase) -> some View {
        switch phase {
        case .welcome:
            return LinearGradient(colors: [Color.bgPrimary, Color.roseGold.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .questionnaire:
            return LinearGradient(colors: [Color.bgPrimary, Color.bgSecondary], startPoint: .top, endPoint: .bottom)
        case .personalizedResponse:
            return LinearGradient(colors: [Color.bgSecondary, Color.lavender.opacity(0.2)], startPoint: .top, endPoint: .bottom)
        case .warning:
            return LinearGradient(colors: [Color.bgPrimary, Color.roseDeep.opacity(0.1)], startPoint: .top, endPoint: .bottom)
        case .completed:
            return LinearGradient(colors: [Color.bgPrimary, Color.green.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private func buttonTextForPhase(_ phase: OnboardingPhase) -> String {
        switch phase {
        case .welcome: return "Get Started"
        case .questionnaire: return selectedGoal != nil ? "Continue" : ""
        case .personalizedResponse: return "Next"
        case .warning: return "I Understand & Accept"
        case .completed: return "Enter LumeSync"
        }
    }
    
    private func nextPhase() {
        TranceHaptics.shared.medium()
        if currentPhase == .completed {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            dismiss()
        } else if let next = OnboardingPhase(rawValue: currentPhase.rawValue + 1) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                currentPhase = next
            }
        }
    }
    
    private func previousPhase() {
        TranceHaptics.shared.light()
        if let prev = OnboardingPhase(rawValue: currentPhase.rawValue - 1) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                currentPhase = prev
            }
        }
    }
    
    private func warningBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(.roseDeep)
                .padding(.top, 6)
            
            Text(text)
                .font(TranceTypography.caption)
                .foregroundColor(.secondary)
            
            Spacer(minLength: 0)
        }
    }
    
    private func progressIndicator() -> some View {
        HStack(spacing: 8) {
            ForEach(1..<OnboardingPhase.allCases.count - 1, id: \.self) { index in
                Capsule()
                    .fill(currentPhase.rawValue >= index ? Color.bwTheta : Color.gray.opacity(0.3))
                    .frame(width: currentPhase.rawValue == index ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentPhase)
            }
        }
    }
    
    private func loadWelcomeSession() -> LightSession? {
        return try? LightScoreReader.loadSession(named: "welcome_introduction")
    }
}
