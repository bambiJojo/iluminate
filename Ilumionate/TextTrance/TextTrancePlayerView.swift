//  TextTrancePlayerView.swift
//  Ilumionate
//
//  Control-free RSVP player. Renders the current word with its pivot letter
//  aligned to a fixed horizontal anchor and tinted with the Trance accent.
//  Tap-and-hold to end (no visible controls, to avoid breaking trance).

import SwiftUI

struct TextTrancePlayerView: View {
    @State private var session: TextTranceSession
    @State private var controlsVisibility = PlayerControlsVisibility()
    @State private var activeSheet: ReaderSheet?
    @State private var resumeAfterSectionSheet = false
    @State private var attentionMonitor = ReaderAttentionMonitor()
    @State private var attentionStatus: ReaderAttentionMonitorStatus = .inactive
    #if DEBUG
    @State private var attentionSample: ReaderAttentionSample?
    @State private var attentionFrameCount = 0
    @State private var attentionLastEvent = "—"
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var appColorScheme

    /// Display preferences with the reader color mode applied (theme swapped
    /// to Dawn/Void as needed). Use for RENDERING; persist the stored prefs.
    private var displayPrefs: ReaderDisplayPreferences {
        session.displayPreferences.resolved(appColorScheme: appColorScheme)
    }

    /// Current modulation for the background visual. Reduce Motion is read from
    /// the environment, so toggling it mid-session pauses the layer immediately.
    private var visualModulation: ReaderVisualModulation {
        ReaderVisualModulator.modulation(
            for: session.currentPhase,
            speedMultiplier: session.speedMultiplier,
            reduceMotion: reduceMotion
        )
    }

    @State private var backgroundPulse = false
    @State private var wordOpacity: Double = 1
    @State private var isScrubbing = false
    @State private var wasPausedBeforeScrub = false
    @State private var playbackTask: Task<Void, Never>?
    private let startIndex: Int

    private enum ReaderSheet: String, Identifiable {
        case settings
        case sections

        var id: String { rawValue }
    }

    init(session: TextTranceSession, startIndex: Int = 0) {
        _session = State(initialValue: session)
        self.startIndex = startIndex
    }

    var body: some View {
        ZStack {
            displayPrefs.adjustedBackground.ignoresSafeArea()

            ReaderVisualLayer(
                visual: displayPrefs.visual,
                modulation: visualModulation,
                opacity: displayPrefs.clampedVisualOpacity
            )

            // Phase-aware atmosphere: the glow color follows the current reading
            // phase (induction → teal, deepening → violet, …), crossfading slowly
            // as phases blend. A slow breath is layered on top. (NOT the
            // entrainment light layer — FlashController only runs post-handoff.)
            RadialGradient(
                colors: [
                    // This gradient IS the `.breath` visual, so it only draws
                    // when breath is selected — otherwise it would double up
                    // underneath whichever shader the listener chose.
                    phaseColor.opacity(
                        displayPrefs.theme.showsPhaseAtmosphere
                            && displayPrefs.visual == .breath
                            ? (backgroundPulse ? 0.24 : 0.10)
                            : 0
                    ),
                    .clear
                ],
                center: .center, startRadius: 20, endRadius: 440)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true),
                           value: backgroundPulse)
                .animation(.easeInOut(duration: 2.5), value: session.currentPhase)

            wordLayer

            if controlsVisibility.isVisible {
                VStack {
                    Spacer()
                    ReaderControlCluster(
                        session: session,
                        onSections: presentSections,
                        onSettings: { activeSheet = .settings },
                        onEnd: { session.end(); dismiss() })
                }
                .opacity(isScrubbing ? 0 : 1)       // clear the stage for the scrub readout
                .animation(.easeInOut(duration: 0.2), value: isScrubbing)
                .transition(.opacity)
            } else if session.isPaused {
                pausedWhisper
            }

            // Whisper-thin reading-progress line pinned to the bottom edge.
            // Faint by default; brightens with controls; drag to scrub the script.
            ScrubWhisperLine(
                fraction: session.progressFraction,
                tint: phaseColor,
                prominent: controlsVisibility.isVisible,
                interactive: session.isReading,
                onScrub: { fraction in
                    if !isScrubbing {
                        isScrubbing = true
                        wasPausedBeforeScrub = session.isPaused
                        if !session.isPaused { session.pause() }
                    }
                    controlsVisibility.registerInteraction()
                    session.seek(toWordIndex: wordIndex(for: fraction))
                },
                onScrubEnd: { fraction in
                    session.seek(toWordIndex: wordIndex(for: fraction), savingProgress: true)
                    if isScrubbing, !wasPausedBeforeScrub { session.resume() }
                    isScrubbing = false
                }
            ) { fraction in
                scrubReadout(for: fraction)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.bottom, TranceSpacing.inner)

            #if DEBUG
            if session.attentionGateEnabled {
                AttentionDebugReadout(
                    sample: attentionSample,
                    status: attentionStatus,
                    isAttentionPaused: session.isAttentionPaused,
                    frameCount: attentionFrameCount,
                    lastEvent: attentionLastEvent
                )
            }
            #endif
        }
        // Resolve adaptive tokens (ORP color, phase atmosphere) to the
        // reader's own color mode, independent of the app-wide theme.
        .environment(\.colorScheme, session.displayPreferences.resolvedScheme(appColorScheme: appColorScheme))
        .contentShape(.rect)
        .gesture(endHoldGesture)
        .simultaneousGesture(revealHideDrag)
        .onTapGesture { controlsVisibility.registerInteraction() }
        .onAppear {
            preparePresentation()
            startPlaybackIfNeeded()
        }
        .platformStatusBarHidden(!controlsVisibility.isVisible)
        .onChange(of: activeSheet) { _, sheet in
            controlsVisibility.isDrawerOpen = sheet != nil
        }
        .onChange(of: session.attentionGateEnabled) { _, _ in
            Task { await syncAttentionMonitor() }
        }
        .onChange(of: session.displayPreferences.hideControls) { _, shouldHide in
            if shouldHide {
                controlsVisibility.hideNow()
            } else {
                controlsVisibility.registerInteraction()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await syncAttentionMonitor() }
            } else {
                attentionMonitor.stop()
            }

            if phase != .active, session.isReading {
                if session.isPaused {
                    session.persistProgress()
                } else {
                    session.pause()
                    controlsVisibility.registerInteraction()
                }
            }
        }
        .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            switch sheet {
            case .settings:
                ReaderSettingsDrawer(session: session, attentionStatus: attentionStatus)
            case .sections:
                ReaderSectionNavigatorSheet(session: session)
            }
        }
        .onDisappear {
            attentionMonitor.stop()
            if session.isReading {
                session.persistProgress()
            }
            ReaderPresetStore.shared.save(
                ReaderPreset(
                    speedTraining: session.speedTraining,
                    displayPreferences: session.displayPreferences
                ),
                forScriptId: session.script.id
            )
        }
    }

    @ViewBuilder
    private var wordLayer: some View {
        if session.isReading {
            AnchoredWord(
                text: session.currentWord,
                pivot: session.currentPivotIndex,
                referenceCharacterCount: session.readerReferenceCharacterCount,
                preferences: displayPrefs
            )
            .opacity(session.isPaused ? 0.4 : wordOpacity)
            .shadow(color: reduceMotion ? .clear : phaseColor.opacity(0.30), radius: 14)
            .onChange(of: session.currentWord) { _, _ in applyWordFade() }
        } else if session.lightActive {
            Text("…")
                .font(.system(size: 40))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var pausedWhisper: some View {
        Text(session.isAttentionPaused ? "Look at screen" : "Paused")
            .font(TranceTypography.caption)
            .foregroundStyle(displayPrefs.secondaryTextColor.opacity(0.7))
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, TranceSpacing.statusBar)
    }

    private func configureAttentionMonitor() {
        attentionMonitor.onUpdate = { isLookingAtScreen, status, _ in
            attentionStatus = status
            if status == .running {
                session.setReaderAttention(isLookingAtScreen: isLookingAtScreen)
            } else if status.disablesGate {
                session.setAttentionGate(enabled: false)
                controlsVisibility.registerInteraction()
            }
        }
        #if DEBUG
        attentionMonitor.onSample = { sample in
            attentionSample = sample
            attentionFrameCount += 1
        }
        attentionMonitor.onDebugEvent = { event in
            attentionLastEvent = event
        }
        #endif
    }

    private func syncAttentionMonitor() async {
        guard session.attentionGateEnabled, scenePhase == .active else {
            attentionMonitor.stop()
            return
        }
        await attentionMonitor.start()
    }

    private func preparePresentation() {
        backgroundPulse = true
        if session.displayPreferences.hideControls {
            controlsVisibility.hideNow()
        } else {
            controlsVisibility.registerInteraction()
        }
        configureAttentionMonitor()
        Task { await syncAttentionMonitor() }
    }

    private func startPlaybackIfNeeded() {
        guard playbackTask == nil, !session.isReading, !session.isComplete else { return }

        playbackTask = Task { @MainActor in
            UsageAnalytics.shared.textTranceStarted()
            await session.begin(from: startIndex)
            playbackTask = nil
            attentionMonitor.stop()
            if session.isComplete {
                UsageAnalytics.shared.textTranceCompleted()
                dismiss()
            }
        }
    }

    private func presentSections() {
        resumeAfterSectionSheet = session.isReading && !session.isPaused
        if resumeAfterSectionSheet {
            session.pause()
        }
        activeSheet = .sections
    }

    private func handleSheetDismiss() {
        guard resumeAfterSectionSheet else { return }
        resumeAfterSectionSheet = false
        session.resume()
    }

    private func wordIndex(for fraction: Double) -> Int {
        guard session.wordCount > 0 else { return 0 }
        return Int((fraction * Double(session.wordCount - 1)).rounded())
    }

    @ViewBuilder
    private func scrubReadout(for fraction: Double) -> some View {
        let index = wordIndex(for: fraction)
        VStack(spacing: TranceSpacing.micro) {
            if let phase = session.phase(atWordIndex: index) {
                Text(phase.displayName.uppercased())
                    .font(TranceTypography.caption)
                    .kerning(1.5)
                    .foregroundStyle(phaseColor)
            }
            Text("word \(index + 1) / \(session.wordCount)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(displayPrefs.textColor)
        }
    }

    /// Atmosphere + word-glow color for the current reading phase.
    private var phaseColor: Color { session.currentPhase.atmosphereColor }

    /// Snap to full opacity for every word, then fade breath/drift words out
    /// across their hold so sentence-ends and ellipses "breathe".
    private func applyWordFade() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { wordOpacity = 1 }

        switch session.currentFade {
        case .none:
            break
        case .breath:
            withAnimation(.easeIn(duration: session.currentDuration)) { wordOpacity = 0.05 }
        case .drift:
            withAnimation(.easeIn(duration: session.currentDuration)) { wordOpacity = 0 }
        }
    }

    private var endHoldGesture: some Gesture {
        LongPressGesture(minimumDuration: 1.2)
            .onEnded { _ in
                session.end()
                dismiss()
            }
    }

    private var revealHideDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                if value.translation.height < -40 {
                    controlsVisibility.registerInteraction()
                } else if value.translation.height > 40 {
                    controlsVisibility.hideNow()
                }
            }
    }
}

/// One word laid out so its pivot letter sits on a fixed center anchor.
/// Monospaced font => constant character advance => simple offset math.
private struct AnchoredWord: View {
    let text: String
    let pivot: Int
    let referenceCharacterCount: Int
    let preferences: ReaderDisplayPreferences

    var body: some View {
        GeometryReader { proxy in
            let layout = TextTranceWordSizing.layout(
                for: text,
                pivot: pivot,
                containerWidth: proxy.size.width,
                referenceCharacterCount: referenceCharacterCount
            )
            let fontSize = min(
                TextTranceWordSizing.maximumFontSize,
                max(TextTranceWordSizing.absoluteMinimumFontSize,
                    layout.fontSize * preferences.clampedFontScale)
            )
            let offsetScale = layout.fontSize > 0 ? fontSize / layout.fontSize : 1

            Text(attributedText(highlighting: layout.safePivot))
            .font(.system(
                size: fontSize,
                weight: preferences.effectiveFontWeight,
                design: preferences.effectiveFont.design
            ))
            .lineSpacing(preferences.lineSpacingPoints)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.55)
            .offset(x: layout.anchorOffset * offsetScale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func attributedText(highlighting safePivot: Int) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = preferences.textColor
        guard safePivot >= 0, safePivot < attributed.characters.count else { return attributed }

        let lowerBound = attributed.characters.index(attributed.startIndex, offsetBy: safePivot)
        let upperBound = attributed.characters.index(after: lowerBound)
        attributed[lowerBound..<upperBound].foregroundColor = preferences.pivotColor
        return attributed
    }
}

#if DEBUG
/// Debug-only live readout of the attention gate's raw signals, so the
/// head-facing / eyes-closed thresholds can be verified and tuned on-device.
/// Compiled out of release builds.
private struct AttentionDebugReadout: View {
    let sample: ReaderAttentionSample?
    let status: ReaderAttentionMonitorStatus
    let isAttentionPaused: Bool
    let frameCount: Int
    let lastEvent: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("attention: \(isAttentionPaused ? "PAUSED" : "reading")")
                .bold()
            // If this stops climbing, the camera stopped delivering frames.
            Text("frames: \(frameCount)")
            Text("event: \(lastEvent)")
            if let sample {
                Text("tracked: \(sample.faceTracked ? "yes" : "no")")
                Text("facing:  \(sample.headFacing, format: .number.precision(.fractionLength(2))) (need > \(ReaderAttentionThresholds.facing, format: .number.precision(.fractionLength(2))))")
                Text("eyesShut: \(sample.eyesClosed, format: .number.precision(.fractionLength(2))) (pause > \(ReaderAttentionThresholds.eyesClosed, format: .number.precision(.fractionLength(2))))")
                Text("rawLooking: \(sample.isLookingAtScreen ? "yes" : "no")")
            } else {
                Text("status: \(String(describing: status))")
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .allowsHitTesting(false)
    }
}
#endif

#Preview {
    let script = TranceScript(
        schemaVersion: 1, id: "p", title: "Preview", theme: .relaxation,
        supportedArcs: [.fullText], language: "en",
        source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
        segments: [TranceScriptSegment(phase: .induction,
            text: "drifting softly downward now",
            pacing: SegmentPacing(baseWPM: 60), arcs: nil, triggersHandoff: nil)])
    let session = TextTranceSession(
        script: script,
        settings: TextTranceSessionSettings(arc: .fullText, speedMultiplier: 0.75,
            lightEnabled: false, binauralEnabled: false,
            beatFrequency: 10, postHandoffDuration: 0),
        light: nil, audio: nil)
    return TextTrancePlayerView(session: session)
}
