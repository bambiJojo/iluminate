//
//  HomeCurrentCard.swift
//  Ilumionate
//
//  What is playing right now, and the way back into it.
//
//  Home renders this only while `NowPlayingState.shared.isActive`, and
//  ContentView suppresses the floating MiniPlayerBar on the home tab in
//  exchange — the same track announced twice on one screen is noise, not
//  reassurance. Reopening the player stays ContentView's job; this card only
//  reports the tap, because the full-screen cover it rebuilds from
//  `NowPlayingState` has no business being duplicated here.
//
//  Headed with LibraryShelfSectionHeader and built from LiminalCard so Current
//  and the Continue section directly below it read as one pair.
//

import SwiftUI

struct HomeCurrentCard: View {
    let nowPlaying: NowPlayingState
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            LibraryShelfSectionHeader(title: "Current")

            Button(action: onOpen) {
                LiminalCard {
                    HStack(spacing: TranceSpacing.list) {
                        Image(systemName: "waveform")
                            .font(.title3)
                            .foregroundStyle(Color.roseGold)
                            .frame(width: 36, height: 36)
                            .background(Color.roseGold.opacity(0.12), in: .rect(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                            Text(nowPlaying.currentTitle)
                                .font(TranceTypography.sectionTitle)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)

                            Text(statusLabel)
                                .font(TranceTypography.caption)
                                .foregroundStyle(Color.textSecondary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(Color.roseGold)
                            .contentTransition(.symbolEffect(.replace))

                        ProgressRingView(progress: nowPlaying.progress)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current: \(nowPlaying.currentTitle)")
            .accessibilityValue(statusLabel)
            .accessibilityHint("Opens the full player")
        }
    }

    private var isPlaying: Bool {
        nowPlaying.playbackState == .playing
    }

    private var statusLabel: String {
        switch nowPlaying.playbackState {
        case .playing:   "Playing"
        case .paused:    "Paused"
        case .countdown: "Starting…"
        case .complete:  "Completed"
        case .idle:      "Ready"
        }
    }
}

// MARK: - Preview

#Preview {
    struct HomeCurrentCardPreview: View {
        @State private var nowPlaying = NowPlayingState.shared

        var body: some View {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                HomeCurrentCard(nowPlaying: nowPlaying, onOpen: {})
                    .padding(TranceSpacing.screen)
            }
            .onAppear {
                nowPlaying.activate(
                    mode: .flashMode(
                        frequency: 10,
                        intensity: 0.8,
                        colorTemperature: 3_000,
                        pattern: .sine,
                        binauralEnabled: false,
                        binauralCarrier: 200,
                        binauralVolume: 0.5
                    ),
                    title: "Hypnagogic Drift",
                    engine: LightEngine()
                )
                nowPlaying.updateProgress(0.42)
            }
        }
    }

    return HomeCurrentCardPreview()
}
