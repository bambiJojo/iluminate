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
            Color.bgPrimary.ignoresSafeArea()

            // Subtle decorative pulse (NOT the entrainment light layer —
            // FlashController only runs in the post-handoff tail in M1).
            RadialGradient(
                colors: [Color.roseGold.opacity(backgroundPulse ? 0.22 : 0.08), .clear],
                center: .center, startRadius: 20, endRadius: 420)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true),
                           value: backgroundPulse)

            if session.isReading {
                AnchoredWord(text: session.currentWord, pivot: session.currentPivotIndex)
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

    var body: some View {
        let chars = Array(text)
        let safePivot = chars.isEmpty ? 0 : min(max(pivot, 0), chars.count - 1)

        HStack(spacing: 0) {
            ForEach(chars.indices, id: \.self) { index in
                Text(String(chars[index]))
                    .foregroundStyle(index == safePivot ? Color.roseGold : Color.textPrimary)
            }
        }
        .font(.system(size: 34, weight: .regular, design: .monospaced))
        // Shift the word so the pivot letter's center sits on screen center:
        // offset = -(pivot index relative to word center) * char advance.
        .offset(x: anchorOffset(chars: chars.count, pivot: safePivot))
    }

    private func anchorOffset(chars: Int, pivot: Int) -> CGFloat {
        guard chars > 0 else { return 0 }
        let charWidth: CGFloat = 20.4   // ~34pt SF Mono advance; constant for monospaced
        let wordCenter = CGFloat(chars - 1) / 2
        return (wordCenter - CGFloat(pivot)) * charWidth
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
