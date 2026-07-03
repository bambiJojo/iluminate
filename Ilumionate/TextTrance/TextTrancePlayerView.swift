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
    @State private var showingSettings = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var backgroundPulse = false
    @State private var wordOpacity: Double = 1
    @State private var isScrubbing = false
    @State private var wasPausedBeforeScrub = false
    private let startIndex: Int

    init(session: TextTranceSession, startIndex: Int = 0) {
        _session = State(initialValue: session)
        self.startIndex = startIndex
    }

    var body: some View {
        ZStack {
            Color.voidDeep.ignoresSafeArea()

            // Phase-aware atmosphere: the glow color follows the current reading
            // phase (induction → teal, deepening → violet, …), crossfading slowly
            // as phases blend. A slow breath is layered on top. (NOT the
            // entrainment light layer — FlashController only runs post-handoff.)
            RadialGradient(
                colors: [phaseColor.opacity(backgroundPulse ? 0.24 : 0.10), .clear],
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
                        onSettings: { showingSettings = true },
                        onEnd: { session.end(); dismiss() })
                }
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
                    session.seek(toWordIndex: wordIndex(for: fraction))
                    if isScrubbing, !wasPausedBeforeScrub { session.resume() }
                    isScrubbing = false
                }
            ) { fraction in
                scrubReadout(for: fraction)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.bottom, TranceSpacing.inner)
        }
        .contentShape(.rect)
        .gesture(endHoldGesture)
        .simultaneousGesture(revealHideDrag)
        .onTapGesture { controlsVisibility.registerInteraction() }
        .task {
            backgroundPulse = true
            controlsVisibility.registerInteraction()
            UsageAnalytics.shared.textTranceStarted()
            await session.begin(from: startIndex)
            if session.isComplete {
                UsageAnalytics.shared.textTranceCompleted()
                dismiss()
            }
        }
        .statusBarHidden(!controlsVisibility.isVisible)
        .onChange(of: showingSettings) { _, open in
            controlsVisibility.isDrawerOpen = open
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, session.isReading, !session.isPaused {
                session.pause()
                controlsVisibility.registerInteraction()
            }
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsDrawer(session: session)
        }
        .onDisappear {
            if !session.isComplete { session.end() }
        }
    }

    @ViewBuilder
    private var wordLayer: some View {
        if session.isReading {
            AnchoredWord(
                text: session.currentWord,
                pivot: session.currentPivotIndex,
                referenceCharacterCount: session.readerReferenceCharacterCount
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
        Text("Paused")
            .font(TranceTypography.caption)
            .foregroundStyle(Color.textSecondary.opacity(0.6))
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, TranceSpacing.statusBar)
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
                .foregroundStyle(Color.textPrimary)
        }
    }

    /// Atmosphere + word-glow color for the current reading phase.
    private var phaseColor: Color {
        switch session.currentPhase {
        case .preTalk, .transitional:    return .phaseIntro
        case .induction:                 return .phaseInduction
        case .deepening:                 return .phaseDeepener
        case .fractionation, .confusion: return .phaseFractionation
        case .suggestions, .therapy, .eroticSuggestions, .conditioning, .brainwashing:
            return .phaseSuggestion
        case .emergence:                 return .phaseAwakening
        }
    }

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

    var body: some View {
        GeometryReader { proxy in
            let chars = Array(text)
            let layout = TextTranceWordSizing.layout(
                for: text,
                pivot: pivot,
                containerWidth: proxy.size.width,
                referenceCharacterCount: referenceCharacterCount
            )

            HStack(spacing: 0) {
                ForEach(chars.indices, id: \.self) { index in
                    Text(String(chars[index]))
                        .foregroundStyle(index == layout.safePivot ? Color.auroraTeal : Color.textPrimary)
                }
            }
            .font(.system(size: layout.fontSize, weight: .regular, design: .monospaced))
            .offset(x: layout.anchorOffset)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

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
