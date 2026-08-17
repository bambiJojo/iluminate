//
//  LibraryCreatorsView.swift
//  Ilumionate
//
//  Groups sessions by their creator/narrator for browsing.
//

import SwiftUI

// MARK: - LibraryCreatorsView

struct LibraryCreatorsView: View {

    let audioFiles: [AudioFile]
    @Bindable var engine: LightEngine

    /// Passed straight through to each creator's browse screen — this view owns
    /// no state, it only groups.
    var onDelete: ((AudioFile) -> Void)?

    /// All unique creator names, sorted. Files with no creator → "Unknown"
    private var creators: [(name: String, files: [AudioFile])] {
        let grouped = Dictionary(grouping: audioFiles) { file -> String in
            let creator = file.creatorDisplayName ?? ""
            return creator.isEmpty ? "Unknown" : creator
        }
        return grouped
            .map { (name: $0.key, files: $0.value.sorted { $0.displayName < $1.displayName }) }
            .sorted { lhs, rhs in
                if lhs.name == "Unknown" { return false }
                if rhs.name == "Unknown" { return true }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            if creators.isEmpty || (creators.count == 1 && creators[0].name == "Unknown") {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(creators, id: \.name) { group in
                            NavigationLink {
                                LibraryBrowseView(
                                    title: group.name,
                                    audioFiles: group.files,
                                    engine: engine,
                                    onDelete: onDelete
                                )
                            } label: {
                                CreatorRow(name: group.name, count: group.files.count)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if group.name != creators.last?.name {
                                Rectangle()
                                    .fill(Color.glassBorder.opacity(0.3))
                                    .frame(height: 1)
                                    .padding(.leading, 56)
                            }
                        }
                        Color.clear.frame(height: TranceSpacing.tabBarClearance)
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.top, TranceSpacing.card)
                    .background(Color.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: TranceRadius.glassCard))
                    .overlay(
                        RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                            .strokeBorder(Color.glassBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.top, TranceSpacing.content)
                }
            }
        }
        .navigationTitle("Creators")
        .onAppear { UsageAnalytics.shared.screen(.libraryCreators) }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TranceSpacing.card) {
            Image(systemName: "person.wave.2")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(colors: [.bwTheta, .bwDelta], startPoint: .top, endPoint: .bottom)
                )
            Text("No Creators Yet")
                .font(TranceTypography.greeting)
                .foregroundStyle(.textPrimary)
            Text("Edit a session and add a creator name\nto organize by voice or narrator")
                .font(TranceTypography.body)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(TranceSpacing.screen)
    }
}
// MARK: - CreatorRow

private struct CreatorRow: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            ZStack {
                Circle()
                    .fill(Color.bwTheta.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: name == "Unknown" ? "person.slash" : "person.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.bwTheta)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(TranceTypography.body)
                    .foregroundStyle(.textPrimary)
                Text("\(count) \(count == 1 ? "session" : "sessions")")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textLight)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.textLight)
        }
        .padding(.vertical, TranceSpacing.card)
    }
}
