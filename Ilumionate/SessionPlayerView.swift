//
//  SessionPlayerView.swift
//  Ilumionate
//
//  Redesigned session player with Trance design system
//  Featuring MandalaVisualizer center piece and glass morphism
//

import SwiftUI
import Combine

/// Full-screen session player with Trance design and MandalaVisualizer
struct SessionPlayerView: View {

    let session: LightSession
    let audioFile: AudioFile?
    @Bindable var engine: LightEngine
    @Environment(\.dismiss) private var dismiss

    @State private var player: LightScorePlayer
    @State private var audioSync: AudioSyncController?
    @State private var showingControls = true
    @State private var validationResult: ValidationResult?
    @State private var displayTime: Double = 0.0
    @State private var uiUpdateTimer: Timer?
    @State private var isSyncEnabled = true
    @State private var currentPhase = "Induction Phase"

    init(session: LightSession, audioFile: AudioFile? = nil, engine: LightEngine) {
        self.session = session
        self.audioFile = audioFile
        self.engine = engine
        self.player = LightScorePlayer(session: session)
    }

    var body: some View {
        ZStack {
            // Trance background with rose-gold gradients
            Color.bgPrimary
                .ignoresSafeArea()

            // Ambient light overlay based on engine brightness
            RadialGradient(
                colors: [
                    Color.roseGold.opacity(engine.brightness * 0.4),
                    Color.blush.opacity(engine.brightness * 0.2),
                    .clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 400
            )
            .ignoresSafeArea()
            .blendMode(.softLight)

            // Main player interface
            if showingControls {
                playerInterface
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                // Minimal interface with just mandala
                VStack {
                    Spacer()
                    MandalaVisualizer(size: 250, brightness: engine.brightness)
                    Spacer()

                    // Tap to show controls hint
                    Text("Tap to show controls")
                        .font(TranceTypography.caption)
                        .foregroundColor(.textLight)
                        .padding(.bottom, TranceSpacing.statusBar)
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingControls = true
                    }
                }
                .transition(.opacity)
            }

            // Pause overlay
            if !player.isPlaying && !player.isComplete {
                pauseOverlay
                    .transition(.opacity)
            }
        }
        .onAppear {
            startUITimer()

            // Validate session
            validationResult = SessionDiagnostics.validateSession(session)
            #if DEBUG
            if let result = validationResult {
                print(result.summary)
            }
            #endif

            // Setup audio sync if needed
            if let audioFile = audioFile {
                setupAudioSync(audioFile)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.prepareSession()
                }
            } else {
                prepareSession()
            }

            // Auto-hide controls after 5 seconds only if playing
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if player.isPlaying {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showingControls = false
                    }
                }
            }
        }
        .onDisappear {
            stopUITimer()
            stopSession()
            audioSync?.stop()
        }
        .statusBarHidden(!showingControls)
        .preferredColorScheme(.light) // Force light mode for Trance design
    }

    // MARK: - Main Player Interface

    private var playerInterface: some View {
        VStack(spacing: TranceSpacing.content) {
            // Top controls
            HStack {
                Button {
                    stopSession()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(session.displayName)
                        .font(TranceTypography.trackTitle)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    PhasePill(phase: currentPhase)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingControls = false
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.title3)
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.top, TranceSpacing.statusBar)

            Spacer()

            // Mandala visualizer center piece
            MandalaVisualizer(size: 220, brightness: engine.brightness)
                .padding(.vertical, TranceSpacing.content)

            Spacer()

            // Player controls section
            VStack(spacing: TranceSpacing.cardMargin) {
                // Audio scrubber with time display
                VStack(spacing: TranceSpacing.small) {
                    AudioScrubber(progress: .constant(player.progress)) { newProgress in
                        let newTime = Double(session.duration_sec) * newProgress
                        player.seek(to: newTime)
                    }

                    HStack {
                        Text(formatTime(displayTime))
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                            .monospacedDigit()
                        Spacer()
                        Text(formatTime(Double(session.duration_sec)))
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)

                // Main play button
                Button {
                    TranceHaptics.shared.medium()
                    if player.isPlaying {
                        player.pause()
                        engine.pause()
                        audioSync?.pause()
                    } else {
                        player.play()
                        engine.resume()
                        if audioSync?.hasAudioLoaded == true {
                            audioSync?.play()
                        }
                        
                        // Auto-hide controls after they hit play
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            if player.isPlaying {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    showingControls = false
                                }
                            }
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.roseGold, .roseDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .shadow(
                                color: TranceShadow.button.color,
                                radius: TranceShadow.button.radius,
                                x: TranceShadow.button.x,
                                y: TranceShadow.button.y
                            )

                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .offset(x: player.isPlaying ? 0 : 2) // Optical alignment for play
                    }
                }
                .scaleEffect(player.isPlaying ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: player.isPlaying)

                // Additional controls
                if let audioFile = audioFile {
                    GlassCard(label: "SYNC OPTIONS") {
                        VStack(spacing: TranceSpacing.list) {
                            SyncToggle(isOn: $isSyncEnabled)

                            if audioSync != nil {
                                HStack {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)

                                    Slider(value: Binding(
                                        get: { Double(audioSync?.audioVolume ?? 1.0) },
                                        set: { audioSync?.audioVolume = Float($0) }
                                    ), in: 0.0...1.0)
                                    .tint(.roseGold)

                                    Text("\(Int((audioSync?.audioVolume ?? 1.0) * 100))%")
                                        .font(TranceTypography.caption)
                                        .foregroundColor(.textSecondary)
                                        .frame(width: 32)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                }

                // Brightness control
                GlassCard(label: "LIGHT INTENSITY") {
                    HStack {
                        Image(systemName: "sun.min.fill")
                            .font(.caption)
                            .foregroundColor(.textSecondary)

                        Slider(value: $engine.userBrightnessMultiplier, in: 0.1...1.0)
                            .tint(.roseGold)

                        Image(systemName: "sun.max.fill")
                            .font(.caption)
                            .foregroundColor(.textSecondary)

                        Text("\(Int(engine.userBrightnessMultiplier * 100))%")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                            .frame(width: 32)
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
            }
            .padding(.bottom, TranceSpacing.statusBar)
        }
        .animation(.easeInOut(duration: 0.3), value: showingControls)
    }

    // MARK: - Pause Overlay

    private var pauseOverlay: some View {
        ZStack {
            Color.bgPrimary.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: TranceSpacing.content) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.roseGold)

                Text("Session Paused")
                    .font(TranceTypography.trackTitle)
                    .foregroundColor(.textPrimary)

                Text("Tap play to continue")
                    .font(TranceTypography.body)
                    .foregroundColor(.textSecondary)
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingControls = true
            }
        }
    }


    // MARK: - Session Control

    private func prepareSession() {
        #if DEBUG
        print("🚀 prepareSession() - \(session.displayName)")
        print("⏱ Duration: \(session.duration_sec)s, Moments: \(session.light_score.count)")
        print(SessionDiagnostics.logSessionDetails(session))
        #endif

        // Attach the player to the engine
        engine.attachSession(player: player)

        // Start the engine if not already running, but pause it immediately
        if !engine.isRunning {
            engine.start()
        }
        engine.pause()
        
        // Ensure player is loaded but paused
        player.seek(to: 0.0)
    }

    private func stopSession() {
        player.stop()
        engine.detachSession()
        engine.stop()
        audioSync?.stop()
    }

    // MARK: - Audio Sync

    private func setupAudioSync(_ audioFile: AudioFile) {
        print("🎵 Setting up audio sync for: \(audioFile.filename)")

        audioSync = AudioSyncController()

        // Load audio asynchronously to prevent UI freezing
        Task {
            do {
                try await audioSync?.loadAudioAsync(from: audioFile.url)

                await MainActor.run {
                    // Sync callbacks
                    audioSync?.onTimeUpdate = { _ in }

                    audioSync?.onPlaybackFinished = {
                        stopSession()
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    print("❌ Failed to setup audio: \(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }


    // MARK: - Timer Management

    private func startUITimer() {
        stopUITimer() // Ensure no duplicate timers
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                self.displayTime = self.player.currentTime
            }
        }
    }

    private func stopUITimer() {
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = nil
    }
}

// MARK: - Preview

#Preview {
    let engine = LightEngine()
    let session = LightSession(
        session_name: "Preview Session",
        duration_sec: 300,
        light_score: [
            LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
            LightMoment(time: 150, frequency: 6, intensity: 0.8, waveform: .softPulse),
            LightMoment(time: 300, frequency: 12, intensity: 0.3, waveform: .sine)
        ]
    )

    return SessionPlayerView(session: session, engine: engine)
}
