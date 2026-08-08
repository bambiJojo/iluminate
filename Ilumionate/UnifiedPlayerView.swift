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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Live pull-to-reveal state. Held here rather than in a child view
    /// because revealing removes the minimal overlay mid-gesture, so `onEnded`
    /// may never fire and this has to be resettable from outside.
    @State private var pullOrigin: CGPoint?
    @State private var pullProgress: Double = 0
    @State private var hasRevealedThisPull = false
    /// Overlay size, so the pull target can be aimed at the centre line.
    @State private var overlaySize: CGSize = .zero

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

            // Layer 5: Session opening — the threshold arc, or the numeric
            // countdown when VoiceOver needs something to announce.
            if viewModel.countdownValue != nil || viewModel.countdownMessage != nil {
                Group {
                    if let threshold = viewModel.thresholdController, !viewModel.usesNumericCountdown {
                        ThresholdView(
                            controller: threshold,
                            message: viewModel.countdownMessage,
                            onSkip: viewModel.skipCountdown
                        )
                    } else {
                        PlayerCountdownOverlay(
                            count: viewModel.countdownValue,
                            message: viewModel.countdownMessage
                        )
                    }
                }
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
        .onReceive(NotificationCenter.default.publisher(for: PlatformAudioSession.interruptionNotification)) {
            viewModel.handleAudioSessionInterruption($0)
        }
        .onChange(of: controlsVisibility.isVisible) { _, visible in
            withAnimation(LiminalMotion.fade) { viewModel.showingControls = visible }
        }
        .onChange(of: viewModel.showingControls) { _, showing in
            if showing {
                controlsVisibility.registerInteraction()
            } else {
                // Reset as the minimal overlay comes back, not as it leaves.
                // Revealing tears the overlay down mid-gesture so its onEnded
                // may never fire; clearing on the way in guarantees a clean
                // slate rather than a puck stranded from the previous pull.
                endPull()
            }
        }
        .onChange(of: viewModel.showingTrackList) { _, open in
            controlsVisibility.isDrawerOpen = open || showingOverflow
        }
        .onChange(of: showingOverflow) { _, open in
            controlsVisibility.isDrawerOpen = open || viewModel.showingTrackList
        }
        .onChange(of: viewModel.playbackState, initial: true) { _, state in
            // Anything other than playing keeps the controls up: a paused or
            // not-yet-started session should never leave the user looking at a
            // still screen with nothing to touch.
            controlsVisibility.isPaused = state != .playing
        }
        .platformStatusBarHidden(!viewModel.showingControls)
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

        case .visualField:
            // Reads the view model's live copy, not the mode's snapshot, so the
            // in-session Strength and Speed tiles take effect immediately.
            VisualFieldStage(
                settings: viewModel.visualFieldSettings,
                fade: viewModel.visualFieldFade,
                isPaused: viewModel.playbackState != .playing
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
        // Deliberately not a Button. A full-screen Button claims every touch
        // sequence that begins on it, which silently swallowed the reveal
        // swipe attached to the ZStack above. This owns its own gesture so
        // nothing competes for the touch.
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
                MandalaVisualizer(
                    size: 250,
                    brightness: viewModel.engine.brightness,
                    isPlaying: viewModel.isPlaying
                )
                Spacer()
            }

            // Fades out as the pull begins — the affordance takes over the
            // job of saying what to do.
            Text("Swipe up to show controls")
                .font(TranceTypography.caption)
                .foregroundStyle(
                    viewModel.secondaryLabelColor.opacity(0.5 * (1 - pullProgress))
                )
                .padding(.bottom, TranceSpacing.statusBar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { overlaySize = $0 }
        .overlay {
            if let pullOrigin {
                PullToRevealAffordance(
                    origin: pullOrigin,
                    containerSize: overlaySize,
                    progress: pullProgress
                )
                .transition(.opacity)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Once a pull has fired, ignore the rest of it. The finger
                    // is usually still down, and without this the next event
                    // would re-create the puck that the reveal just cleared.
                    guard !hasRevealedThisPull else { return }

                    if pullOrigin == nil {
                        withAnimation(reduceMotion ? nil : LiminalMotion.touch) {
                            pullOrigin = value.startLocation
                        }
                    }
                    pullProgress = MinimalOverlayGesture.progress(
                        for: value.translation,
                        from: value.startLocation,
                        in: overlaySize
                    )

                    // Commit on arrival, not on release: eyes shut, the user
                    // wants confirmation the moment the gesture succeeds.
                    if pullProgress >= 1, !hasRevealedThisPull {
                        hasRevealedThisPull = true
                        TranceHaptics.shared.medium()
                        controlsVisibility.registerInteraction()
                        // Drop the puck immediately rather than leaving it
                        // rendered at full progress during the fade-out.
                        pullOrigin = nil
                    }
                }
                .onEnded { _ in endPull() }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Swipe up to show controls")
        .accessibilityAddTraits(.isButton)
        // VoiceOver intercepts swipes, so without this override there would be
        // no way for a VoiceOver user to reach the controls at all.
        .accessibilityAction { controlsVisibility.registerInteraction() }
    }

    /// Spring the puck back and clear the affordance. Safe to call more than
    /// once — revealing tears the overlay down mid-gesture, so this also runs
    /// from the `showingControls` observer.
    private func endPull() {
        hasRevealedThisPull = false
        withAnimation(reduceMotion ? nil : LiminalMotion.touch) {
            pullProgress = 0
            pullOrigin = nil
        }
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

            PlayerControlTray(
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
