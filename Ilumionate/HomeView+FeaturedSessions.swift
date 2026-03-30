//
//  HomeView+FeaturedSessions.swift
//  Ilumionate
//
//  Time-of-day featured sessions carousel for the Home dashboard.
//

import SwiftUI

extension HomeView {

    // MARK: - Featured Sessions Section

    var featuredSessionsSection: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            // Section header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeOfDayLabel)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("\(featuredSessions.count) sessions curated for now")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button {
                    TranceHaptics.shared.light()
                    showingSessionLibrary = true
                } label: {
                    HStack(spacing: 4) {
                        Text("See All")
                            .font(TranceTypography.caption)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.roseGold)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TranceSpacing.micro)

            // Horizontal card carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TranceSpacing.list) {
                    ForEach(featuredSessions) { session in
                        FeaturedSessionCard(session: session) {
                            TranceHaptics.shared.heavy()
                            selectedSession = session
                            showingSessionPlayer = true
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.micro)
                .padding(.vertical, TranceSpacing.micro)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Time-of-Day Logic

    /// Sessions reordered so the most relevant appear first for the current hour.
    var featuredSessions: [LightSession] {
        guard !sessions.isEmpty else { return [] }
        let prioritized = timeOfDayPriority.compactMap { keyword in
            sessions.first { $0.displayName.localizedCaseInsensitiveContains(keyword) }
        }
        let usedIDs = Set(prioritized.map(\.id))
        let rest = sessions.filter { !usedIDs.contains($0.id) }
        return prioritized + rest
    }

    private var timeOfDayLabel: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Morning Sessions"
        case 12..<17: return "Afternoon Sessions"
        case 17..<22: return "Evening Sessions"
        default:      return "Night Sessions"
        }
    }

    /// Display-name keywords ranked by relevance for the current hour.
    private var timeOfDayPriority: [String] {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  // Morning — energise and awaken
            return ["Sunrise", "Gamma", "Defrag", "SMR"]
        case 12..<17: // Afternoon — clarity and creativity
            return ["Defrag", "Gamma", "Creativity", "Bilateral"]
        case 17..<22: // Evening — wind down and integrate
            return ["Anxiety", "Schumann", "Peniston", "Creativity"]
        default:      // Night — deep rest
            return ["Delta", "SMR", "Hypnagogic", "Hypnosis"]
        }
    }
}
