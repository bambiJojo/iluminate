//
//  AudioLightPlayerView.swift
//  Ilumionate
//
//  Unified full-screen audio player. Works for any audio file regardless of
//  analysis state. A "Light Sync" button inside the player reflects the current
//  analysis status and lets the user enable synced light therapy once analysis
//  is complete — or prioritise the file in the analysis queue.
//

import SwiftUI
import Combine

// MARK: - Light Sync Status

private enum LightSyncStatus {
    case enabled
    case ready
    case analyzing(progress: Double, stage: String)
    case queued(position: Int)
    case unavailable
}

// MARK: - AudioLightPlayerView

struct AudioLightPlayerView: View {
    let audioFile: AudioFile
    @Bindable var engine: LightEngine
    @Environment(\.dismiss) private var dismiss

    @State private var player: AudioLightSyncPlayer?
    @State private var showingControls = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var volumePercentage: Int = 100
    @State private var lightSyncEnabled = false
    @State private var lightSession: LightSession?
    @State private var showingLightSyncWarning = false
    @State private var pendingLightSession: LightSession?
    @AppStorage("hasSeenLightSyncWarning") private var hasSeenLightSyncWarning = false

    private var analysisManager: AnalysisStateManager { AnalysisStateManager.shared }
    private let uiUpdateTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var lightSyncStatus: LightSyncStatus {
        if lightSyncEnabled { return .enabled }
        if lightSession != nil { return .ready }
        if let current = analysisManager.currentAnalysis,
           current.audioFile.id == audioFile.id {
            return .analyzing(progress: current.progress, stage: stageLabel(current.stage))
        }
        let pos = analysisManager.queuePosition(for: audioFile)
        if pos > 0 { return .queued(position: pos) }
        return .unavailable
    }

    var body: some View {
        ZStack {
            if lightSyncEnabled {
                SessionView(engine: engine)
            } else {
                Color.bgPrimary.ignoresSafeArea()
            }

            SessionLockView { player?.stop(); dismiss() }

            if player == nil && !showError {
                ProgressView("Loading…")
                    .tint(lightSyncEnabled ? .white : .roseGold)
                    .foregroundStyle(lightSyncEnabled ? .white : Color.textPrimary)
            }

            if showingControls, let player = player {
                controlsOverlay(player: player).transition(.opacity)
            }

            if !showingControls && player != nil { floatingShowButton }
        }
        .task { await loadPlayer() }
        .onDisappear { player?.stop() }
        .onReceive(uiUpdateTimer) { _ in
            if let activePlayer = player { volumePercentage = Int(activePlayer.volume * 100) }
        }
        .onChange(of: analysisManager.completedAnalyses.count) {
            Task { await checkForLightSession() }
        }
        .statusBar(hidden: !showingControls)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: { Text(errorMessage) }
        .alert("Flashing Lights Warning", isPresented: $showingLightSyncWarning) {
            Button("I Understand", role: .none) {
                hasSeenLightSyncWarning = true
                if let session = pendingLightSession, let player = player {
                    withAnimation(.easeInOut(duration: 0.4)) { lightSyncEnabled = true }
                    player.enableLightSync(lightSession: session)
                }
                pendingLightSession = nil
            }
            Button("Cancel", role: .cancel) { pendingLightSession = nil }
        } message: {
            Text("Light Sync uses rapidly flashing light patterns. If you have photosensitive epilepsy or are sensitive to flashing lights, do not enable this feature.\n\nConsult a doctor before use if you have any concerns.")
        }
    }

    // MARK: - Controls Overlay

    private func controlsOverlay(player: AudioLightSyncPlayer) -> some View {
        VStack {
            topBar(player: player)
            Spacer()
            VStack(spacing: 16) {
                lightSyncButton(player: player)
                progressControl(player: player)
                volumeControl(player: player)
                if lightSyncEnabled { brightnessControl.transition(.opacity.combined(with: .scale(scale: 0.95))) }
                transportControls(player: player)
                Text("Tap screen to exit")
                    .font(.caption)
                    .foregroundStyle(labelColor.opacity(0.5))
                    .padding(.bottom, 40)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Sub-views

    private var labelColor: Color { lightSyncEnabled ? .white : .textPrimary }

    private func topBar(player: AudioLightSyncPlayer) -> some View {
        HStack {
            Button { player.stop(); dismiss() } label: {
                Image(systemName: "house.fill").font(.title3).foregroundStyle(labelColor)
            }
            Spacer()
            VStack(alignment: .center) {
                Text(audioFile.displayName).font(.headline).foregroundStyle(labelColor).lineLimit(1)
                Text(player.formatTime(player.currentTime) + " / " + player.formatTime(player.duration))
                    .font(.caption).monospacedDigit().foregroundStyle(labelColor.opacity(0.7))
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { showingControls = false }
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.title3).foregroundStyle(labelColor)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func progressControl(player: AudioLightSyncPlayer) -> some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                in: 0...max(player.duration, 1)
            )
            .tint(lightSyncEnabled ? .white : .roseGold)
            HStack {
                Text(player.formatTime(player.currentTime)).font(.caption2).monospacedDigit()
                Spacer()
                Text("-" + player.formatTime(max(0, player.duration - player.currentTime)))
                    .font(.caption2).monospacedDigit()
            }
            .foregroundStyle(labelColor.opacity(0.6))
        }
    }

    private func volumeControl(player: AudioLightSyncPlayer) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(labelColor.opacity(0.7))
                Slider(
                    value: Binding(get: { Double(player.volume) }, set: { player.setVolume(Float($0)) }),
                    in: 0...1
                )
                .tint(lightSyncEnabled ? .white : .roseGold)
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(labelColor.opacity(0.7))
            }
            Text("Audio: \(volumePercentage)%").font(.caption2).foregroundStyle(labelColor.opacity(0.6))
        }
        .padding(.horizontal).padding(.vertical, 12)
        .background(.ultraThinMaterial).cornerRadius(12)
    }

    private var brightnessControl: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "sun.min.fill").font(.caption).foregroundStyle(Color.white.opacity(0.7))
                Slider(value: $engine.userBrightnessMultiplier, in: 0.1...1.0).tint(.white)
                Image(systemName: "sun.max.fill").font(.caption).foregroundStyle(Color.white.opacity(0.7))
            }
            Text("Brightness: \(Int(engine.userBrightnessMultiplier * 100))%")
                .font(.caption2).foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.horizontal).padding(.vertical, 12)
        .background(.ultraThinMaterial).cornerRadius(12)
    }

    private func transportControls(player: AudioLightSyncPlayer) -> some View {
        HStack(spacing: 40) {
            Button { player.seek(to: max(0, player.currentTime - 15)) } label: {
                Image(systemName: "gobackward.15").font(.title2).foregroundStyle(labelColor)
            }
            Button {
                if player.isPlaying { player.pause() } else { player.play() }
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(lightSyncEnabled ? Color.white : Color.roseGold)
            }
            Button { player.seek(to: min(player.duration, player.currentTime + 15)) } label: {
                Image(systemName: "goforward.15").font(.title2).foregroundStyle(labelColor)
            }
        }
    }

    private var floatingShowButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { showingControls = true }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .foregroundStyle(lightSyncEnabled ? Color.white : Color.textPrimary)
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

    // MARK: - Light Sync Button

    @ViewBuilder
    private func lightSyncButton(player: AudioLightSyncPlayer) -> some View {
        Button {
            TranceHaptics.shared.medium()
            handleLightSyncTap(player: player)
        } label: {
            HStack(spacing: 8) {
                switch lightSyncStatus {
                case .enabled:
                    Image(systemName: "lightbulb.fill"); Text("Light Sync On")
                case .ready:
                    Image(systemName: "lightbulb"); Text("Enable Light Sync")
                case .analyzing(let progress, let stage):
                    ProgressView().controlSize(.small).tint(lightSyncEnabled ? .white : .roseGold)
                    Text("\(stage) · \(Int(progress * 100))%")
                case .queued(let position):
                    Image(systemName: "clock")
                    Text(position == 1 ? "Next in queue" : "#\(position) in queue · Prioritize")
                case .unavailable:
                    Image(systemName: "sparkles"); Text("Analyze for Light Sync")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(lightSyncEnabled ? Color.roseGold : Color.textPrimary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(lightSyncEnabled ? Color.roseGold.opacity(0.15) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 20)
                .stroke(lightSyncEnabled ? Color.roseGold : Color.glassBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func handleLightSyncTap(player: AudioLightSyncPlayer) {
        switch lightSyncStatus {
        case .enabled:
            withAnimation(.easeInOut(duration: 0.4)) { lightSyncEnabled = false }
            player.disableLightSync()
        case .ready:
            guard let session = lightSession else { return }
            if hasSeenLightSyncWarning {
                withAnimation(.easeInOut(duration: 0.4)) { lightSyncEnabled = true }
                player.enableLightSync(lightSession: session)
            } else {
                pendingLightSession = session
                showingLightSyncWarning = true
            }
        case .analyzing:
            break
        case .queued(let position):
            if position > 1 { analysisManager.prioritizeInQueue(audioFile: audioFile) }
        case .unavailable:
            Task { await analysisManager.queueForAnalysis(audioFile) }
        }
    }

    // MARK: - Player Setup

    private func loadPlayer() async {
        let syncPlayer = AudioLightSyncPlayer(lightEngine: engine)
        do {
            try await syncPlayer.loadAudio(audioFile: audioFile)
            player = syncPlayer
            syncPlayer.play()
            await checkForLightSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.3)) { showingControls = false }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func checkForLightSession() async {
        guard lightSession == nil else { return }
        let sessionsURL = URL.documentsDirectory.appendingPathComponent("GeneratedSessions", isDirectory: true)
        let baseName = audioFile.filename
            .replacing(".mp3", with: "").replacing(".m4a", with: "").replacing(".wav", with: "")
        let fileURL = sessionsURL.appendingPathComponent("\(baseName)_session.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        if let data = try? Data(contentsOf: fileURL),
           let session = try? JSONDecoder().decode(LightSession.self, from: data) {
            lightSession = session
        }
    }

    private func stageLabel(_ stage: AnalysisStage) -> String {
        switch stage {
        case .starting: return "Starting"
        case .transcribing: return "Transcribing"
        case .analyzing: return "Analyzing"
        case .generatingSession: return "Generating"
        case .complete: return "Complete"
        case .failed: return "Failed"
        }
    }
}

#Preview {
    @Previewable @State var engine = LightEngine()
    let audioFile = AudioFile(filename: "Test Audio.mp3", duration: 600, fileSize: 1024000)
    AudioLightPlayerView(audioFile: audioFile, engine: engine)
}
