//
//  OnboardingView.swift
//  LumeSync
//
//  Created by Claude on 3/5/26.
//

import SwiftUI
import AVFoundation

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
    @State private var welcomeSession: LightSession?
    @State private var lightEngine = LightEngine()
    @State private var cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isRequestingCameraPermission = false
    
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
        case attentionPermission
        case analyticsConsent
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
                    case .attentionPermission:
                        attentionPermissionPhase
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    case .analyticsConsent:
                        analyticsConsentPhase
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
            welcomeSession = loadWelcomeSession()
            UsageAnalytics.shared.screen(.onboarding)
        }
        .onChange(of: currentPhase) { _, newPhase in
            UsageAnalytics.shared.onboardingStep(index: newPhase.rawValue)
            if newPhase == .completed {
                applyGoalPreferences()
                UsageAnalytics.shared.onboardingCompleted()
            }
        }
        .platformFullScreenCover(isPresented: $showWelcomeSession, onDismiss: finishWelcomeSession) {
            if let welcomeSession {
                UnifiedPlayerView(
                    mode: .session(session: welcomeSession, audioFile: nil),
                    engine: lightEngine
                )
            }
        }
        .platformPersistentSystemOverlaysHidden()
        .platformStatusBarHidden()
        .onAppear {
            #if canImport(UIKit)
            AppDelegate.orientationLock = UIInterfaceOrientationMask.portrait
            #endif
        }
        .onDisappear {
            #if canImport(UIKit)
            AppDelegate.orientationLock = UIInterfaceOrientationMask.all
            #endif
        }
    }
    
    // MARK: - Navigation Footer
    @ViewBuilder
    private var navigationFooter: some View {
        if currentPhase == .attentionPermission
            || currentPhase == .analyticsConsent
            || currentPhase == .completed {
            EmptyView()
        } else {
            HStack {
                // Back Button
                if currentPhase != .welcome && currentPhase != .completed {
                    Button(action: previousPhase) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(.white)
                    .padding(.horizontal, (currentPhase == .questionnaire && selectedGoal == nil) ? 0 : 20)
                    .frame(width: (currentPhase == .questionnaire && selectedGoal == nil) ? 50 : nil, height: 50)
                    .background(Color.roseGold)
                    .clipShape(Capsule())
                    .shadow(color: Color.roseGold.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .disabled(currentPhase == .questionnaire && selectedGoal == nil)
                .opacity((currentPhase == .questionnaire && selectedGoal == nil) ? 0.5 : 1)
                .animation(.easeInOut, value: selectedGoal)
            }
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
                    .foregroundStyle(Color.warmAccent)
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
                    .foregroundStyle(.primary)
                
                Text("Your personal hypnosis audio player and mind machine for deep relaxation and transformation.")
                    .font(TranceTypography.body)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
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
                                .foregroundStyle(selectedGoal == goal ? .white : .roseGold)
                                .frame(width: 30)
                            
                            Text(goal.rawValue)
                                .font(TranceTypography.body)
                                .foregroundStyle(selectedGoal == goal ? .white : .primary)
                            
                            Spacer()
                            
                            if selectedGoal == goal {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white)
                                    .matchedGeometryEffect(id: "check", in: animation)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedGoal == goal ? Color.roseGold : Color.white.opacity(0.1))
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
                        .fill(Color.roseGold.opacity(0.2))
                        .frame(width: 140, height: 140)
                    
                    Image(systemName: goal.icon)
                        .font(.system(size: 60))
                        .foregroundStyle(.roseGold)
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
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(.roseGold)
                .shadow(color: .roseGold.opacity(0.5), radius: 10, x: 0, y: 5)
                .padding(.top, 20)
            
            VStack(spacing: 16) {
                Text("Important Warning")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.primary)
                
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

    // 5. Reader Attention Permission Phase
    private var attentionPermissionPhase: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(Color.roseGold.opacity(0.16))
                    .frame(width: 140, height: 140)

                Image(systemName: cameraAuthorization == .authorized ? "eye.fill" : "eye")
                    .font(.system(size: 62, weight: .light))
                    .foregroundStyle(Color.roseGold)
            }
            .padding(.top, 20)

            VStack(spacing: 16) {
                Text("Keep the reader in sync")
                    .font(TranceTypography.screenTitle)
                    .multilineTextAlignment(.center)

                Text("The optional attention check uses the front camera to pause the reader when you look away and resume when you return.")
                    .font(TranceTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 12) {
                permissionBullet("Face tracking is processed on your device.")
                permissionBullet("LumeSync does not record or save camera images.")
                permissionBullet("The camera runs only while reader attention is enabled.")
            }

            if cameraAuthorization == .authorized {
                Label("Camera access enabled", systemImage: "checkmark.circle.fill")
                    .font(TranceTypography.body.weight(.semibold))
                    .foregroundStyle(Color.roseGold)
            } else if cameraAuthorization == .denied {
                Text("Camera access was declined. You can enable it later in iOS Settings.")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if cameraAuthorization == .restricted {
                Text("Camera access is restricted on this device. The reader will work without attention check.")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    if cameraAuthorization == .notDetermined {
                        requestCameraPermission()
                    } else {
                        nextPhase()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isRequestingCameraPermission {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: cameraAuthorization == .authorized ? "arrow.right" : "camera.fill")
                        }
                        Text(attentionPermissionButtonTitle)
                    }
                    .font(TranceTypography.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.roseGold)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRequestingCameraPermission)

                if cameraAuthorization == .notDetermined {
                    Button("Not Now") { nextPhase() }
                        .font(TranceTypography.body.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                        .disabled(isRequestingCameraPermission)
                }
            }
        }
    }

    // 6. Analytics Consent Phase
    private var analyticsConsentPhase: some View {
        VStack(spacing: 28) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 68, weight: .light))
                .foregroundStyle(Color.roseGold)
                .shadow(color: .roseGold.opacity(0.35), radius: 12, x: 0, y: 6)
                .padding(.top, 20)

            VStack(spacing: 16) {
                Text("Help improve LumeSync")
                    .font(TranceTypography.screenTitle)
                    .multilineTextAlignment(.center)

                Text("Share anonymous app usage analytics so we can understand what works, find problems, and make the app better.")
                    .font(TranceTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 12) {
                analyticsBullet("Includes screen views, feature usage, completion buckets, and non-content error categories.")
                analyticsBullet("Never includes audio, transcripts, generated session text, imported documents, or reading-source URLs.")
                analyticsBullet("You can change this anytime in Settings.")
            }

            VStack(spacing: 12) {
                Button {
                    chooseAnalyticsConsent(true)
                } label: {
                    Text("Share Anonymous Analytics")
                        .font(TranceTypography.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.roseGold)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    chooseAnalyticsConsent(false)
                } label: {
                    Text("Not Now")
                        .font(TranceTypography.body.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // 7. Completed Phase
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
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 16) {
                Text("You're ready.")
                    .font(TranceTypography.screenTitle)

                Text("Begin with a short guided session, or explore the app and choose your own path.")
                    .font(TranceTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            OnboardingCompletionActionsView(
                canStartSession: welcomeSession != nil,
                onStartSession: { completeOnboarding(with: .startWelcomeSession) },
                onExploreApp: { completeOnboarding(with: .exploreApp) }
            )
            .padding(.horizontal, 10)
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
            return LinearGradient(colors: [Color.bgPrimary, Color.roseGold.opacity(0.1)], startPoint: .top, endPoint: .bottom)
        case .attentionPermission:
            return LinearGradient(colors: [Color.bgPrimary, Color.roseGold.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .analyticsConsent:
            return LinearGradient(colors: [Color.bgPrimary, Color.roseGold.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
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
        case .attentionPermission: return ""
        case .analyticsConsent: return ""
        case .completed: return "Enter LumeSync"
        }
    }

    private func chooseAnalyticsConsent(_ enabled: Bool) {
        UsageAnalytics.shared.setEnabled(enabled)
        nextPhase()
    }

    private var attentionPermissionButtonTitle: String {
        switch cameraAuthorization {
        case .notDetermined:
            isRequestingCameraPermission ? "Requesting Access…" : "Enable Attention Check"
        case .authorized:
            "Continue"
        case .denied, .restricted:
            "Continue Without It"
        @unknown default:
            "Continue"
        }
    }

    private func requestCameraPermission() {
        guard !isRequestingCameraPermission else { return }
        isRequestingCameraPermission = true
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
            isRequestingCameraPermission = false
        }
    }
    
    private func nextPhase() {
        TranceHaptics.shared.medium()
        if currentPhase == .completed {
            completeOnboarding(with: .exploreApp)
        } else if let next = OnboardingPhase(rawValue: currentPhase.rawValue + 1) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                currentPhase = next
            }
        }
    }

    private func completeOnboarding(with action: OnboardingCompletionAction) {
        TranceHaptics.shared.medium()
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        UsageAnalytics.shared.onboardingCompletionAction(action)

        switch action {
        case .startWelcomeSession where welcomeSession != nil:
            showWelcomeSession = true
        case .startWelcomeSession, .exploreApp:
            dismiss()
        }
    }

    private func finishWelcomeSession() {
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
        dismiss()
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
                .foregroundStyle(.roseGold)
                .padding(.top, 6)
            
            Text(text)
                .font(TranceTypography.caption)
                .foregroundStyle(.secondary)
            
            Spacer(minLength: 0)
        }
    }

    private func analyticsBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.roseGold)
                .padding(.top, 2)

            Text(text)
                .font(TranceTypography.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private func permissionBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.roseGold)
                .padding(.top, 2)

            Text(text)
                .font(TranceTypography.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }
    
    private func progressIndicator() -> some View {
        HStack(spacing: 8) {
            // Welcome is already behind them — start the bar with a completed step
            // so the user never sees a demoralizing "0% / nothing done" (goal-gradient).
            Circle()
                .fill(Color.roseGold)
                .frame(width: 8, height: 8)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(.white)
                )

            ForEach(1..<OnboardingPhase.allCases.count - 1, id: \.self) { index in
                Capsule()
                    .fill(currentPhase.rawValue >= index ? Color.roseGold : Color.textLight.opacity(0.4))
                    .frame(width: currentPhase.rawValue == index ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentPhase)
            }
        }
    }
    
    private func loadWelcomeSession() -> LightSession? {
        return try? LightScoreReader.loadSession(named: "welcome_introduction")
    }

    /// Persists the chosen goal and seeds session-generation preferences so the
    /// first generated session already matches the user's intent (smart defaults).
    private func applyGoalPreferences() {
        guard let goal = selectedGoal else { return }
        UserDefaults.standard.set(goal.rawValue, forKey: "profileGoal")

        guard let seed = goal.recommendedPreferenceSeed else { return }
        let preferences = AnalysisPreferences.shared
        preferences.frequencyProfile = seed.frequencyProfile
        preferences.transitionStyle = seed.transitionStyle
        preferences.colorTempMode = seed.colorTempMode
        preferences.intensityMultiplier = seed.intensityMultiplier
        preferences.bilateralMode = seed.bilateralMode
        preferences.contentHint = seed.contentHint
    }
}
