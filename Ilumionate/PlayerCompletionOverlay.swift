//
//  PlayerCompletionOverlay.swift
//  Ilumionate
//

import SwiftUI

struct PlayerCompletionOverlay: View {
    let title: String
    let duration: TimeInterval
    let onReplay: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: TranceSpacing.content) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.roseGold)
                    .accessibilityHidden(true)

                VStack(spacing: TranceSpacing.micro) {
                    Text("Session complete")
                        .font(.title2)
                        .bold()

                    Text(title)
                        .font(.headline)

                    if duration > 0 {
                        Text("You completed (Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))).")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)

                VStack(spacing: TranceSpacing.list) {
                    Button("Repeat session", systemImage: "arrow.counterclockwise", action: onReplay)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    Button("Done", systemImage: "checkmark", action: onDone)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            .foregroundStyle(.white)
            .padding(TranceSpacing.screen)
        }
    }
}
