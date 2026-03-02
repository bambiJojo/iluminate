//
//  SessionPlayerView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/9/26.
//

import SwiftUI
import Combine

/// Full-screen session player with controls and progress display
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
    private let uiUpdateTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(session: LightSession, audioFile: AudioFile? = nil, engine: LightEngine) {
        self.session = session
        self.audioFile = audioFile
        self.engine = engine
        self.player = LightScorePlayer(session: session)
    }

    var body: some View {
        ZStack {
            // Background - driven by engine brightness
            SessionView(engine: engine)

            // Lock overlay (always present, invisible until activated)
            SessionLockView {
                stopSession()
                dismiss()
            }

            // Controls overlay
            if showingControls {
                controlsOverlay
                    .transition(.opacity)
            }

            // Floating controls button (always visible when controls are hidden)
            if !showingControls {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingControls = true
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding()
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            print("🎬 SessionPlayerView appeared")
            print("📊 Session: \(session.displayName)")

            // Validate session before starting
            validationResult = SessionDiagnostics.validateSession(session)
            if let result = validationResult {
                print(result.summary)

                // Log any warnings or errors
                for error in result.errors {
                    print("❌ Error:", error)
                }
                for warning in result.warnings {
                    print("⚠️ Warning:", warning)
                }

                // Analyze session
                let analysis = SessionDiagnostics.analyzeSession(session)
                print("📊 Effectiveness:", analysis.estimatedEntrainmentEffectiveness.emoji,
                      analysis.estimatedEntrainmentEffectiveness.rawValue)

                if !analysis.suggestions.isEmpty {
                    print("💡 Suggestions:")
                    for suggestion in analysis.suggestions {
                        print("  -", suggestion)
                    }
                }
            }

            print("⚡️ Starting session...")

            // Setup audio sync if audio file is provided
            if let audioFile = audioFile {
                setupAudioSync(audioFile)
            }

            startSession()

            // Hide controls after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingControls = false
                }
            }
        }
        .onDisappear {
            print("🛑 SessionPlayerView disappeared")
            stopSession()
            audioSync?.stop()
        }
        .onReceive(uiUpdateTimer) { _ in
            displayTime = player.currentTime
        }
        .statusBar(hidden: !showingControls)
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                // Home button
                Button {
                    stopSession()
                    dismiss()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .center) {
                    Text(session.displayName)
                        .font(.headline)
                    Text(formatTime(displayTime) + " / " + session.durationFormatted)
                        .font(.caption)
                        .monospacedDigit()
                }

                Spacer()

                // Hide controls button
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingControls = false
                    }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            .padding()
            .background(.ultraThinMaterial)

            Spacer()

            // Bottom controls
            VStack(spacing: 16) {
                // Progress bar
                ProgressView(value: player.progress)
                    .tint(.white)

                // Audio volume control (if audio is present)
                if audioSync != nil {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "speaker.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))

                            Slider(value: Binding(
                                get: { audioSync?.audioVolume ?? 1.0 },
                                set: { audioSync?.audioVolume = Float($0) }
                            ), in: 0.0...1.0)
                                .tint(.white)

                            Image(systemName: "speaker.wave.3.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Text("Audio: \(Int((audioSync?.audioVolume ?? 1.0) * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }

                // Brightness control
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "sun.min.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        Slider(value: $engine.userBrightnessMultiplier, in: 0.1...1.0)
                            .tint(.white)

                        Image(systemName: "sun.max.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Text("Brightness: \(Int(engine.userBrightnessMultiplier * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(12)

                // Playback controls
                HStack(spacing: 40) {
                    Button {
                        if player.isPlaying {
                            player.pause()
                            audioSync?.pause()
                        } else {
                            player.play()
                            audioSync?.play()
                        }
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                    }
                    .disabled(player.isComplete)
                }

                // Exit hint
                Text("Tap screen to exit")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 40)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(.white)
        .onTapGesture {
            // Tap controls area to keep them visible
        }
    }

    // MARK: - Session Control

    private func startSession() {
        print("🚀 startSession() called")
        print("📝 Session: \(session.displayName)")
        print("⏱ Duration: \(session.duration_sec)s")
        print("📊 Light score moments: \(session.light_score.count)")

        // Log session details in debug builds
        #if DEBUG
        print(SessionDiagnostics.logSessionDetails(session))
        #endif

        // Attach the player to the engine
        engine.attachSession(player: player)
        print("🔗 Player attached to engine")

        // Start the engine if not already running
        if !engine.isRunning {
            print("▶️ Starting engine...")
            engine.start()
            print("✅ Engine started, isRunning: \(engine.isRunning)")
        } else {
            print("⚠️ Engine already running")
        }

        // Start playback
        print("▶️ Starting player...")
        player.play()
        print("✅ Player started, isPlaying: \(player.isPlaying)")

        // Start audio if available
        if audioSync?.hasAudioLoaded == true {
            audioSync?.play()
            print("▶️ Audio playback started")
        }

        // Check initial state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let engineSnapshot = SessionDiagnostics.captureEngineState(self.engine)
            let playerSnapshot = SessionDiagnostics.capturePlayerState(self.player)

            print("📊 Engine state after 0.5s:")
            print(engineSnapshot.description)
            print("\n📊 Player state after 0.5s:")
            print(playerSnapshot.description)
        }
    }

    private func stopSession() {
        print("🛑 stopSession() called")
        player.stop()
        engine.detachSession()
        engine.stop()
        audioSync?.stop()
    }

    // MARK: - Audio Sync

    private func setupAudioSync(_ audioFile: AudioFile) {
        print("🎵 Setting up audio sync for: \(audioFile.filename)")

        audioSync = AudioSyncController()

        do {
            try audioSync?.loadAudio(from: audioFile.url)

            // Sync callbacks - keep lights synchronized with audio time
            audioSync?.onTimeUpdate = { [weak player] _ in
                // Optional: Update UI with current time
                // For now, lights are driven by their own timer
            }

            audioSync?.onPlaybackFinished = {
                print("🏁 Audio finished, stopping session")
                stopSession()
                dismiss()
            }

            print("✅ Audio sync ready")
        } catch {
            print("❌ Failed to setup audio: \(error)")
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
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
