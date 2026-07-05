//
//  HomeView+MySessions.swift
//  Ilumionate
//
//  "Your Sessions" shelf — light scores the user generated from their own audio.
//  Given the top shelf so the thing they built is the first thing they see
//  (endowment effect).
//

import SwiftUI

/// Pairs a user-generated light score with the audio file it was built from,
/// so tapping a card can launch synchronized audio + light playback.
struct MyGeneratedSessionItem: Identifiable {
    let audioFile: AudioFile
    let session: LightSession

    var id: UUID { audioFile.id }
}

extension HomeView {

    // MARK: - My Sessions Section

    var mySessionsSection: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Sessions")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Generated from your audio")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, TranceSpacing.micro)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TranceSpacing.list) {
                    ForEach(myGeneratedSessions) { item in
                        FeaturedSessionCard(session: item.session) {
                            TranceHaptics.shared.heavy()
                            playerFile = item.audioFile
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.micro)
                .padding(.vertical, TranceSpacing.micro)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Loading

    /// Most-recent-first list of audio files that have a saved generated session.
    func loadMyGeneratedSessions() -> [MyGeneratedSessionItem] {
        audioFiles
            .sorted { $0.createdDate > $1.createdDate }
            .compactMap { file in
                guard let session = GeneratedSessionStore.shared.load(for: file) else { return nil }
                return MyGeneratedSessionItem(audioFile: file, session: session)
            }
    }
}
