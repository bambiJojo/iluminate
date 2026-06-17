//  TextTrancePlayerView.swift
//  Ilumionate
//
//  Control-free RSVP player. Renders the current word with its pivot letter
//  aligned to a fixed horizontal anchor and tinted with the Trance accent.
//  Tap-and-hold to end (no visible controls, to avoid breaking trance).

import SwiftUI

struct TextTrancePlayerView: View {
    @State private var session: TextTranceSession
    @Environment(\.dismiss) private var dismiss

    @State private var backgroundPulse = false

    init(session: TextTranceSession) {
        _session = State(initialValue: session)
    }

    var body: some View {
        ZStack {
            Color.voidDeep.ignoresSafeArea()

            // Subtle decorative pulse (NOT the entrainment light layer —
            // FlashController only runs in the post-handoff tail in M1).
            RadialGradient(
                colors: [Color.auroraTeal.opacity(backgroundPulse ? 0.22 : 0.08), .clear],
                center: .center, startRadius: 20, endRadius: 420)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true),
                           value: backgroundPulse)

            if session.isReading {
                AnchoredWord(
                    text: session.currentWord,
                    pivot: session.currentPivotIndex,
                    referenceCharacterCount: session.readerReferenceCharacterCount
                )
            } else if session.lightActive {
                Text("…")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .contentShape(.rect)
        .gesture(endHoldGesture)
        .task {
            backgroundPulse = true
            await session.begin()
            if session.isComplete { dismiss() }
        }
        .statusBarHidden()
        .onDisappear {
            if !session.isComplete { session.end() }
        }
    }

    private var endHoldGesture: some Gesture {
        LongPressGesture(minimumDuration: 1.2)
            .onEnded { _ in
                session.end()
                dismiss()
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
        settings: TextTranceSessionSettings(arc: .fullText, speed: .slow,
            lightEnabled: false, binauralEnabled: false,
            beatFrequency: 10, postHandoffDuration: 0),
        light: nil, audio: nil)
    return TextTrancePlayerView(session: session)
}
