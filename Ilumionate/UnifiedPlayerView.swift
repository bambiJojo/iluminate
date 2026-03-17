//
//  UnifiedPlayerView.swift
//  Ilumionate
//
//  Single cohesive player view handling all playback modes:
//  session, flash, color pulse, audio, and playlist.
//

import SwiftUI

struct UnifiedPlayerView: View {
    @State private var viewModel: UnifiedPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    init(mode: PlayerMode, engine: LightEngine) {
        _viewModel = State(initialValue: UnifiedPlayerViewModel(mode: mode, engine: engine))
    }

    var body: some View {
        ZStack {
            // Layer 1: Background visual surface
            backgroundLayer

            // Layer 2: Session lock overlay
            SessionLockView {
                viewModel.stopAll()
                dismiss()
            }

            // Layer 3: Controls / minimal overlay
            if viewModel.showingControls {
                controlsOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                minimalOverlay
                    .transition(.opacity)
            }

            // Layer 4: Pause overlay (only when controls are hidden so it doesn't block the play button)
            if viewModel.playbackState == .paused && viewModel.countdownValue == nil && !viewModel.showingControls {
                PlayerPauseOverlay {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.showingControls = true
                    }
                }
                .transition(.opacity)
            }

            // Layer 5: Countdown overlay
            if let count = viewModel.countdownValue {
                PlayerCountdownOverlay(count: count)
                    .transition(.opacity)
                    .zIndex(10)
            }

            // Layer 6: Safety warning (blocks everything)
            if viewModel.showingSafetyWarning {
                PlayerSafetyWarningView(
                    mode: viewModel.mode,
                    onAcknowledge: { viewModel.acknowledgeSafetyWarning() },
                    onCancel: { dismiss() }
                )
                .zIndex(20)
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .statusBarHidden(!viewModel.showingControls)
        .preferredColorScheme(viewModel.useDarkChrome ? .dark : .light)
        .sheet(isPresented: $viewModel.showingTrackList) {
            PlayerTrackListSheet(viewModel: viewModel)
        }
        .onChange(of: AnalysisStateManager.shared.completedAnalyses.count) {
            Task { await viewModel.checkForLightSession() }
        }
        .alert("Flashing Lights Warning", isPresented: lightSyncWarningBinding) {
            Button("I Understand", role: .none) {
                if let session = viewModel.lightSession {
                    viewModel.enableLightSync(session: session)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Light Sync uses rapidly flashing light patterns. If you have photosensitive epilepsy or are sensitive to flashing lights, do not enable this feature.")
        }
    }

    // MARK: - Light Sync Warning Binding

    private var lightSyncWarningBinding: Binding<Bool> {
        Binding(
            get: {
                if case .ready = viewModel.lightSyncStatus,
                   !UserDefaults.standard.bool(forKey: "hasSeenLightSyncWarning") {
                    return false // only shown when user taps the button
                }
                return false
            },
            set: { _ in }
        )
    }

    // MARK: - Background Layer

    @ViewBuilder
    private var backgroundLayer: some View {
        switch viewModel.mode {
        case .session:
            SessionPlayerBackground(engine: viewModel.engine)

        case .flashMode(_, _, let colorTemp, _, _, _, _):
            if let controller = viewModel.flashController {
                FlashGridBackground(controller: controller, colorTemperature: colorTemp)
            } else {
                Color.black.ignoresSafeArea()
            }

        case .colorPulse(let frequency, let intensity):
            ColorPulseBackground(
                frequency: frequency,
                intensity: intensity,
                isPaused: viewModel.playbackState == .paused
            )

        case .audioLight:
            AudioLightBackground(
                engine: viewModel.engine,
                lightSyncEnabled: viewModel.lightSyncEnabled
            )

        case .playlist:
            SessionView(engine: viewModel.engine)
        }
    }

    // MARK: - Minimal Overlay (controls hidden)

    private var minimalOverlay: some View {
        VStack {
            // Floating show-controls button
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.showingControls = true
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .foregroundStyle(viewModel.labelColor)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(.circle)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding()
            }

            Spacer()

            // Mandala in session mode
            if viewModel.mode.hasMandalaVisualizer {
                MandalaVisualizer(size: 250, brightness: viewModel.engine.brightness)
                Spacer()
            }

            // Timer display for infinite modes
            if viewModel.mode.hasFrequencyDisplay {
                timerDisplay
            }

            Text("Tap to show controls")
                .font(TranceTypography.caption)
                .foregroundStyle(viewModel.secondaryLabelColor.opacity(0.6))
                .padding(.bottom, TranceSpacing.statusBar)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.showingControls = true
            }
        }
    }

    private var timerDisplay: some View {
        Text(viewModel.formatTime(viewModel.currentTime))
            .font(TranceTypography.caption)
            .foregroundStyle(viewModel.secondaryLabelColor)
            .monospacedDigit()
            .padding(.bottom, TranceSpacing.content)
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // Top bar
            PlayerTopBar(
                viewModel: viewModel,
                onClose: {
                    viewModel.stopAll()
                    dismiss()
                },
                onMinimize: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.showingControls = false
                    }
                }
            )

            Spacer()

            // Center visualizer (session mode)
            if viewModel.mode.hasMandalaVisualizer {
                MandalaVisualizer(size: 220, brightness: viewModel.engine.brightness)
                    .padding(.vertical, TranceSpacing.content)
                Spacer()
            }

            // Bottom controls panel
            bottomControls
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showingControls)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            // Scrubber (session, audio, playlist)
            if viewModel.mode.hasAudioScrubber {
                PlayerScrubberSection(viewModel: viewModel)
            }

            // Transport controls (always)
            PlayerTransportSection(viewModel: viewModel)

            // Light sync button (audio mode)
            if viewModel.mode.hasLightSyncToggle {
                PlayerLightSyncButton(viewModel: viewModel)
            }

            // Sync options (session with audio)
            if viewModel.mode.hasSyncOptions {
                sessionSyncOptions
            }

            // Volume (when applicable)
            if viewModel.mode.hasVolumeControl {
                PlayerVolumeSection(viewModel: viewModel)
            }

            // Flash mode controls
            if viewModel.mode.hasBilateralToggle || viewModel.mode.hasBinauralToggle {
                flashModeControls
            }

            // Brightness (session, audio with sync, playlist)
            if viewModel.mode.hasBrightnessControl {
                PlayerBrightnessSection(
                    engine: viewModel.engine,
                    labelColor: viewModel.labelColor
                )
            }

            // Smart transitions (playlist)
            if viewModel.mode.hasSmartTransitions {
                smartTransitionsToggle
            }

            // Track list button (playlist)
            if viewModel.mode.hasTrackList {
                trackListButton
            }
        }
        .padding(.bottom, TranceSpacing.statusBar)
    }

    // MARK: - Flash Mode Controls

    private var flashModeControls: some View {
        HStack(spacing: 32) {
            if viewModel.mode.hasBilateralToggle {
                PlayerBilateralSection(viewModel: viewModel)
            }
            if viewModel.mode.hasBinauralToggle {
                PlayerBinauralSection(viewModel: viewModel)
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
    }

    // MARK: - Session Sync Options

    private var sessionSyncOptions: some View {
        GlassCard(label: "SYNC OPTIONS") {
            VStack(spacing: TranceSpacing.list) {
                SyncToggle(isOn: $viewModel.isSyncEnabled)

                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(viewModel.secondaryLabelColor)

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.volume) },
                            set: { viewModel.setVolume(Float($0)) }
                        ),
                        in: 0.0...1.0
                    )
                    .tint(.roseGold)

                    Text("\(Int(viewModel.volume * 100))%")
                        .font(TranceTypography.caption)
                        .foregroundStyle(viewModel.secondaryLabelColor)
                        .frame(width: 32)
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
    }

    // MARK: - Smart Transitions Toggle

    private var smartTransitionsToggle: some View {
        HStack {
            Toggle("Smart Transitions", isOn: Binding(
                get: { viewModel.smartTransitions },
                set: { viewModel.smartTransitions = $0 }
            ))
            .font(.caption)
            .tint(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal, TranceSpacing.screen)
    }

    // MARK: - Track List Button

    private var trackListButton: some View {
        Button {
            viewModel.showingTrackList = true
        } label: {
            Label("Track List", systemImage: "list.number")
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: 20))
        }
        .foregroundStyle(viewModel.labelColor)
    }
}

// MARK: - Preview

#Preview("Session Mode") {
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
    UnifiedPlayerView(mode: .session(session: session, audioFile: nil), engine: engine)
}

#Preview("Flash Mode") {
    UnifiedPlayerView(
        mode: .flashMode(
            frequency: 10.0, intensity: 0.75, colorTemperature: 3000,
            pattern: .sine, binauralEnabled: false, binauralCarrier: 200, binauralVolume: 0.5
        ),
        engine: LightEngine()
    )
}
