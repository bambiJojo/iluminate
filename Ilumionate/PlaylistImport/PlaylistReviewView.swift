//
//  PlaylistReviewView.swift
//  Ilumionate
//

import SwiftUI

struct PlaylistReviewView: View {
    let plan: PlaylistImportPlan
    let audioFiles: [AudioFile]
    let isDownloading: (PlaylistImportPlan.Row.ID) -> Bool
    let downloadError: (PlaylistImportPlan.Row.ID) -> String?
    let onChoose: (PlaylistImportPlan.Row) -> Void
    let onDownload: (PlaylistImportPlan.Row) -> Void
    /// Binds a likely-duplicate row to the library file it matched.
    let onUseExisting: (PlaylistImportPlan.Row, AudioFile.ID) -> Void
    /// Fetches a fresh copy despite the likely match.
    let onDownloadAnyway: (PlaylistImportPlan.Row) -> Void
    let onDownloadAll: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(plan.sourcePlaylist.title)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(.textPrimary)

                    Text(summary)
                        .font(TranceTypography.caption)
                        .foregroundStyle(plan.unresolvedCount == 0 ? .textSecondary : .orange)
                }
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.bgCard)
            } header: {
                Text("Playlist")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textSecondary)
            }

            Section {
                ForEach(plan.rows) { row in
                    PlaylistMatchRow(
                        row: row,
                        selectedAudioFile: selectedAudioFile(for: row),
                        isDownloading: isDownloading(row.id),
                        downloadError: downloadError(row.id),
                        onChoose: { onChoose(row) },
                        onDownload: { onDownload(row) },
                        possibleDuplicate: possibleDuplicate(for: row),
                        onUseExisting: {
                            guard case .possibleDuplicate(let id) = row.status else { return }
                            onUseExisting(row, id)
                        },
                        onDownloadAnyway: { onDownloadAnyway(row) }
                    )
                    .listRowBackground(Color.bgCard)
                }
            } header: {
                Text("Local Matches")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textSecondary)
            } footer: {
                Text("Only matched files are added automatically. Download a publisher-hosted track only when you have permission and source authorization to save it.")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textLight)
            }

            if !plan.downloadableRows.isEmpty {
                Section {
                    Button(action: onDownloadAll) {
                        Label(
                            "Download \(plan.downloadableRows.count) Missing \(plan.downloadableRows.count == 1 ? "Track" : "Tracks")",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(TranceTypography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.roseGold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.bgCard)
                } footer: {
                    Text("Fetches each missing track from the publisher. Continue only if you have permission and source authorization to save every track.")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textLight)
                }
            }

            Section {
                Button(action: onStartOver) {
                    Label("Use a Different Link", systemImage: "arrow.counterclockwise")
                        .font(TranceTypography.body)
                        .foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.bgCard)
            }
        }
        .platformInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
    }

    private var summary: String {
        let matchedCount = plan.matchedCount
        let unresolvedCount = plan.unresolvedCount

        if unresolvedCount == 0 {
            return "\(matchedCount) tracks ready to import"
        }

        return "\(matchedCount) matched, \(unresolvedCount) need attention"
    }

    private func possibleDuplicate(
        for row: PlaylistImportPlan.Row
    ) -> AudioFile? {
        guard case .possibleDuplicate(let id) = row.status else { return nil }
        return audioFiles.first { $0.id == id }
    }

    private func selectedAudioFile(
        for row: PlaylistImportPlan.Row
    ) -> AudioFile? {
        guard let selectedAudioFileID = row.selectedAudioFileID else {
            return nil
        }

        return audioFiles.first { $0.id == selectedAudioFileID }
    }
}
