import SwiftUI

struct LibraryReadingContinuation: Equatable {
    let title: String
    let wordIndex: Int
}

struct LibraryContinuationSection: View {
    let listening: [PlaybackProgressSnapshot]
    let reading: LibraryReadingContinuation?
    let onContinueListening: (PlaybackProgressSnapshot) -> Void
    let onContinueReading: () -> Void

    var body: some View {
        if listening.isEmpty == false || reading != nil {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                LibraryShelfSectionHeader(title: "Continue")

                ForEach(listening.prefix(3)) { snapshot in
                    Button {
                        onContinueListening(snapshot)
                    } label: {
                        continuationRow(
                            title: snapshot.title,
                            detail: remainingText(snapshot),
                            systemImage: snapshot.kind == .audio ? "waveform" : "sparkles"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let reading {
                    Button(action: onContinueReading) {
                        continuationRow(
                            title: reading.title,
                            detail: "Resume near word \(reading.wordIndex + 1)",
                            systemImage: "text.book.closed"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func continuationRow(title: String, detail: String, systemImage: String) -> some View {
        LiminalCard {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.roseGold)
                    .frame(width: 36, height: 36)
                    .background(Color.roseGold.opacity(0.12), in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(title)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .foregroundStyle(Color.roseGold)
            }
        }
    }

    private func remainingText(_ snapshot: PlaybackProgressSnapshot) -> String {
        let remaining = max(0, snapshot.duration * (1 - snapshot.progress))
        return "\(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond))) remaining"
    }
}
