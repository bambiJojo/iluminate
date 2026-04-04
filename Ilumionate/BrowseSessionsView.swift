//
//  BrowseSessionsView.swift
//  Ilumionate
//
//  Full-page session browser extracted from MindMachineView.
//  Shows all bundled research sessions with category filtering.
//

import SwiftUI

struct BrowseSessionsView: View {

    let sessions: [LightSession]
    let engine: LightEngine

    @State private var selectedCategory: MindMachineModel.SessionCategory = .all
    @State private var selectedSession: LightSession?

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: TranceSpacing.list) {
                    SessionCategoryBar(selected: $selectedCategory)
                        .padding(.horizontal, TranceSpacing.screen)

                    Divider()
                        .padding(.horizontal, TranceSpacing.screen)

                    let filtered = filteredSessions
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(
                                filtered.enumerated(),
                                id: \.element.id
                            ) { index, session in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, TranceSpacing.screen + 44)
                                }
                                SessionBrowseRow(session: session) {
                                    TranceHaptics.shared.heavy()
                                    selectedSession = session
                                }
                            }
                        }
                    }
                }
                .padding(.top, TranceSpacing.list)
                .padding(.bottom, TranceSpacing.tabBarClearance)
            }
        }
        .navigationTitle("Research Sessions")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $selectedSession) { session in
            UnifiedPlayerView(
                mode: .session(session: session, audioFile: nil),
                engine: engine
            )
        }
    }

    // MARK: - Filtering

    private var filteredSessions: [LightSession] {
        guard selectedCategory != .all else { return sessions }
        return sessions.filter { session in
            switch selectedCategory {
            case .all:
                true
            case .sleep:
                session.brainwaveCategory == .sleep
            case .relax:
                session.brainwaveCategory == .relax
            case .focus:
                session.brainwaveCategory == .focus
                    || session.brainwaveCategory == .energy
            case .trance:
                session.brainwaveCategory == .trance
                    || session.displayName.localizedStandardContains("hypnos")
                    || session.displayName.localizedStandardContains("trance")
                    || session.displayName.localizedStandardContains("peniston")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TranceSpacing.small) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 40))
                .foregroundStyle(Color.roseGold.opacity(0.4))
            Text("No sessions in this category")
                .font(TranceTypography.body)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TranceSpacing.content)
    }
}

// MARK: - Session Browse Row

private struct SessionBrowseRow: View {
    let session: LightSession
    let onPlay: () -> Void

    var body: some View {
        Button {
            onPlay()
        } label: {
            HStack(spacing: TranceSpacing.list) {
                // Brainwave color indicator
                Circle()
                    .fill(categoryColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(session.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)

                        if let first = session.light_score.first {
                            Text("·")
                                .foregroundStyle(Color.textLight)
                            Text(
                                first.frequency.formatted(
                                    .number.precision(.fractionLength(1))
                                ) + " Hz"
                            )
                            .font(TranceTypography.caption)
                            .foregroundStyle(categoryColor)
                        }
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.roseGold)
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.vertical, TranceSpacing.list)
        }
        .buttonStyle(.plain)
    }

    private var categoryColor: Color {
        switch session.brainwaveCategory {
        case .sleep:  .bwDelta
        case .relax:  .bwTheta
        case .focus:  .bwAlpha
        case .energy: .bwBeta
        case .trance: .bwGamma
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BrowseSessionsView(sessions: [], engine: LightEngine())
    }
}
