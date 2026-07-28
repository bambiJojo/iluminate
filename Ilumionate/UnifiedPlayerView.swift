//
//  UnifiedPlayerView.swift
//  Ilumionate
//
//  Single cohesive player view handling all playback modes:
//  session, flash, color pulse, audio, and playlist.
//

import SwiftUI
import AVFoundation

struct UnifiedPlayerView: View {
    @State private var viewModel: UnifiedPlayerViewModel
    @State private var controlsVisibility = PlayerControlsVisibility()
    @State private var showingOverflow = false
    @State private var isScrubbing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(
        mode: PlayerMode,
        engine: LightEngine,
        initialLightSession: LightSession? = nil,
        mindMachineEntryPoint: MindMachineEntryPoint? = nil,
        mindMachineMode: MindMachineMode? = nil
    ) {
        _viewModel = State(initialValue: UnifiedPlayerViewModel(
            mode: mode,
            engine: engine,
            initialLightSession: initialLightSession,
            mindMachineEntryPoint: mindMachineEntryPoint,
            mindMachineMode: mindMachineMode
        ))
    }

    init(viewModel: UnifiedPlayerViewModel) {
        _viewModel = State(initialValue: viewModel)
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
            if viewModel.countdownValue != nil || viewModel.countdownMessage != nil {
                PlayerCountdownOverlay(
                    count: viewModel.countdownValue,
                    message: viewModel.countdownMessage
                )
                .transition(.opacity)
                .zIndex(10)
            }

            if viewModel.playbackState == .complete {
                PlayerCompletionOverlay(
                    title: viewModel.mode.title,
                    duration: viewModel.duration,
                    isSaved: viewModel.isCurrentSessionSaved,
                    canSave: viewModel.canSaveCompletedSession,
                    nextTitle: viewModel.recommendedNextMode?.title,
                    onReplay: viewModel.replayCompletedSession,
                    onSave: viewModel.saveCompletedSession,
                    onNext: startRecommendedNextSession,
                    onDone: finishSession
                )
                .transition(.opacity)
                .zIndex(15)
            }

            if let notice = viewModel.interruptionNotice,
               viewModel.playbackState != .complete {
                PlayerInterruptionBanner(
                    message: notice,
                    onDismiss: viewModel.dismissInterruptionNotice
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .zIndex(12)
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
        .onAppear { controlsVisibility.registerInteraction() }
        .onAppear { UsageAnalytics.shared.screen(.player) }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: scenePhase) { _, phase in
            viewModel.handleScenePhase(phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) {
            viewModel.handleAudioSessionInterruption($0)
        }
        .onChange(of: controlsVisibility.isVisible) { _, visible in
            withAnimation(LiminalMotion.fade) { viewModel.showingControls = visible }
        }
        .onChange(of: viewModel.showingControls) { _, showing in
            if showing { controlsVisibility.registerInteraction() }
        }
        .onChange(of: viewModel.showingTrackList) { _, open in
            controlsVisibility.isDrawerOpen = open || showingOverflow
        }
        .onChange(of: showingOverflow) { _, open in
            controlsVisibility.isDrawerOpen = open || viewModel.showingTrackList
        }
        .statusBarHidden(!viewModel.showingControls)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height < -40 {        // swipe up → reveal
                        controlsVisibility.registerInteraction()
                    } else if value.translation.height > 40 {   // swipe down → hide
                        controlsVisibility.hideNow()
                    }
                }
        )
        // Player is always dark: entrainment visuals need the void backdrop,
        // regardless of the app-wide Pink Aurora theme.
        .preferredColorScheme(.dark)
        .sheet(isPresented: $viewModel.showingTrackList) {
            PlayerTrackListSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingOverflow) {
            PlayerOverflowSheet(viewModel: viewModel)
        }
        .onChange(of: AnalysisStateManager.shared.completedAnalyses.count) {
            Task { await viewModel.checkForLightSession() }
        }
        .alert("Flashing Lights Warning", isPresented: $viewModel.showingLightSyncWarning) {
            Button("I Understand", role: .none) {
                viewModel.acknowledgeLightSyncWarning()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Light Sync uses rapidly flashing light patterns. If you have photosensitive epilepsy or are sensitive to flashing lights, do not enable this feature.")
        }
    }

    private func startRecommendedNextSession() {
        guard let nextMode = viewModel.recommendedNextMode else { return }
        viewModel.recordNextSessionSelection()
        viewModel.stopAll(reason: .completed)
        let nextViewModel = UnifiedPlayerViewModel(mode: nextMode, engine: viewModel.engine)
        viewModel = nextViewModel
        nextViewModel.onAppear()
        controlsVisibility.registerInteraction()
    }

    // MARK: - Background Layer

    @ViewBuilder
    private var backgroundLayer: some View {
        switch viewModel.mode {
        case .session:
            EntrainmentBackground(
                engine: viewModel.engine,
                isActive: viewModel.mindMachineEnabled
            )

        case .flashMode(_, _, let colorTemp, _, _, _, _, _):
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
            EntrainmentBackground(
                engine: viewModel.engine,
                isActive: viewModel.lightSyncEnabled
            )

        case .playlist:
            EntrainmentBackground(
                engine: viewModel.engine,
                isActive: viewModel.mindMachineEnabled
            )
        }
    }

    // MARK: - Minimal Overlay (Pure Void whisper — auto-fades)

    private var minimalOverlay: some View {
        Button {
            controlsVisibility.registerInteraction()
        } label: {
            VStack {
                VStack(spacing: TranceSpacing.micro) {
                    if viewModel.mode.hasFrequencyDisplay || viewModel.mode.hasAudioScrubber {
                        Text(viewModel.formatTime(viewModel.currentTime))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(viewModel.secondaryLabelColor.opacity(0.6))
                    }
                }
                .padding(.top, TranceSpacing.statusBar)

                Spacer()

                if viewModel.mode.hasMandalaVisualizer {
                    MandalaVisualizer(size: 250, brightness: viewModel.engine.brightness, isPlaying: viewModel.isPlaying)
                    Spacer()
                }

                Text("Tap or swipe up to show controls")
                    .font(TranceTypography.caption)
                    .foregroundStyle(viewModel.secondaryLabelColor.opacity(0.5))
                    .padding(.bottom, TranceSpacing.statusBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show controls")
    }

    // MARK: - Controls Overlay

    private var isHeroMode: Bool { viewModel.mode.hasAudioScrubber }

    /// Landscape on iPhone. The hero orb alone is 240pt plus padding, which
    /// pushes the transport and satellite rows off the bottom of a ~380pt
    /// canvas and makes them untappable, so the orb is dropped here.
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            PlayerTopBar(
                viewModel: viewModel,
                showsTitle: !isHeroMode,
                onClose: {
                    viewModel.stopAll()
                    dismiss()
                },
                onMinimize: {
                    viewModel.dismissToMiniPlayer = true
                    dismiss()
                }
            )

            Spacer()

            // Now-playing hero: orb + title block (session / audio / playlist).
            // The orb is dropped in compact height so the controls below it
            // stay on screen and reachable.
            if isHeroMode {
                if !isCompactHeight {
                    PlayerHeroOrb(engine: viewModel.engine, isPlaying: viewModel.isPlaying)
                        .padding(.vertical, TranceSpacing.content)
                }
                PlayerTitleBlock(viewModel: viewModel)
                Spacer()
            }

            bottomControls
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showingControls)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            PlayerTransportSection(
                viewModel: viewModel,
                onInteraction: controlsVisibility.registerInteraction
            )

            PlayerSatelliteRow(
                viewModel: viewModel,
                engine: viewModel.engine,
                showingOverflow: $showingOverflow,
                onInteraction: controlsVisibility.registerInteraction
            )
            .opacity(isScrubbing ? 0 : 1)

            if isHeroMode {
                scrubLine
            }
        }
        .padding(.bottom, TranceSpacing.statusBar)
    }

    private var scrubLine: some View {
        ScrubWhisperLine(
            fraction: viewModel.progress,
            prominent: true,
            onScrub: { _ in
                if !isScrubbing { isScrubbing = true }
                controlsVisibility.registerInteraction()
            },
            onScrubEnd: { fraction in
                viewModel.seekByProgress(fraction)
                isScrubbing = false
            }
        ) { fraction in
            Text(viewModel.formatTime(fraction * viewModel.duration)
                 + " / " + viewModel.formatTime(viewModel.duration))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(viewModel.labelColor)
        }
        .padding(.horizontal, TranceSpacing.screen)
    }

    private func finishSession() {
        viewModel.finishCompletedSession()
        dismiss()
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
