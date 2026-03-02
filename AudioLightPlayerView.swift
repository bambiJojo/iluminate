//
//  AudioLightPlayerView.swift
//  Ilumionate
//
//  Full-screen synchronized audio and light playback view.
//  Matches the immersive experience of SessionPlayerView but adds
//  audio playback controls (volume, seek, progress).
//

import SwiftUI
import Combine

struct AudioLightPlayerView: View {
    let audioFile: AudioFile
    let lightSession: LightSession
    @Bindable var engine: LightEngine
    @Environment(\.dismiss) private var dismiss

    @State private var player: AudioLightSyncPlayer?
    @State private var showingControls = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var volumePercentage: Int = 100
    private let uiUpdateTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Background - driven by engine brightness (the actual light display)
            SessionView(engine: engine)

            // Lock overlay (prevents accidental exit)
            SessionLockView {
                player?.stop()
                dismiss()
            }

            // Loading state
            if player == nil && !showError {
                ProgressView("Loading...")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            // Controls overlay
            if showingControls, let player = player {
                controlsOverlay(player: player)
                    .transition(.opacity)
            }

            // Floating controls button (when controls are hidden)
            if !showingControls && player != nil {
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
        .task {
            await loadPlayer()
        }
        .onDisappear {
            player?.stop()
        }
        .onReceive(uiUpdateTimer) { _ in
            if let player = player {
                volumePercentage = Int(player.volume * 100)
            }
        }
        .statusBar(hidden: !showingControls)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Controls Overlay

    private func controlsOverlay(player: AudioLightSyncPlayer) -> some View {
        VStack {
            // Top bar
            HStack {
                // Home button
                Button {
                    player.stop()
                    dismiss()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .center) {
                    Text(audioFile.filename)
                        .font(.headline)
                        .lineLimit(1)
                    Text(player.formatTime(player.currentTime) + " / " + player.formatTime(player.duration))
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
                // Progress bar with seek
                VStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ), in: 0...max(player.duration, 1))
                    .tint(.white)

                    HStack {
                        Text(player.formatTime(player.currentTime))
                            .font(.caption2)
                            .monospacedDigit()
                        Spacer()
                        Text("-" + player.formatTime(max(0, player.duration - player.currentTime)))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }

                // Audio volume control
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        Slider(value: Binding(
                            get: { Double(player.volume) },
                            set: { player.setVolume(Float($0)) }
                        ), in: 0...1)
                        .tint(.white)

                        Image(systemName: "speaker.wave.3.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Text("Audio: \(volumePercentage)%")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(12)

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
                    // Seek backward
                    Button {
                        player.seek(to: max(0, player.currentTime - 15))
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                    }

                    // Play/Pause
                    Button {
                        if player.isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                    }

                    // Seek forward
                    Button {
                        player.seek(to: min(player.duration, player.currentTime + 15))
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.title2)
                    }
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

    // MARK: - Player Setup

    private func loadPlayer() async {
        let syncPlayer = AudioLightSyncPlayer(lightEngine: engine)

        do {
            try await syncPlayer.loadAudioWithLights(audioFile: audioFile, lightSession: lightSession)
            player = syncPlayer

            // Auto-start playback
            syncPlayer.play()

            // Hide controls after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingControls = false
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("❌ Failed to load player: \(error)")
        }
    }
}

#Preview {
    @Previewable @State var engine = LightEngine()

    let audioFile = AudioFile(
        filename: "Test Audio.mp3",
        url: URL(fileURLWithPath: "/tmp/test.mp3"),
        duration: 600,
        fileSize: 1024000
    )

    let lightSession = LightSession(
        session_name: "Test Session",
        duration_sec: 600,
        light_score: [
            LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)
        ]
    )

    AudioLightPlayerView(
        audioFile: audioFile,
        lightSession: lightSession,
        engine: engine
    )
}
