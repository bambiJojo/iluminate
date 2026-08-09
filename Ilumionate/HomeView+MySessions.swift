//
//  HomeView+MySessions.swift
//  Ilumionate
//
//  "Your Sessions" shelf — light scores the user generated from their own audio.
//  Given the top shelf so the thing they built is the first thing they see
//  (endowment effect).
//

import SwiftUI

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
    func loadMyGeneratedSessions() -> [GeneratedSessionItem] {
        LibraryShelfContent.generatedSessions(from: audioFiles) { file in
            GeneratedSessionStore.shared.load(for: file)
        }
    }
}
