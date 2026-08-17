//
//  BambiCloudPlaylistMatchRow.swift
//  Ilumionate
//

import SwiftUI

struct BambiCloudPlaylistMatchRow: View {
    let row: BambiCloudPlaylistImportPlan.Row
    let selectedAudioFile: AudioFile?
    let isDownloading: Bool
    let downloadError: String?
    let onChoose: () -> Void
    let onDownload: () -> Void
    /// The library file this row may duplicate, when there is one.
    let possibleDuplicate: AudioFile?
    let onUseExisting: () -> Void
    let onDownloadAnyway: () -> Void

    /// Suppressed while the duplicate choice is showing — that row offers its
    /// own download action, and two would be one too many.
    private var canDownload: Bool {
        if case .possibleDuplicate = row.status { return false }
        return selectedAudioFile == nil && row.track.audioURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            HStack(alignment: .top, spacing: TranceSpacing.list) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(row.track.name)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textPrimary)

                    HStack(spacing: TranceSpacing.inner) {
                        Text(
                            Duration.seconds(row.track.duration)
                                .formatted(.time(pattern: .minuteSecond))
                        )
                        Text(statusText)
                    }
                    .font(TranceTypography.caption)
                    .foregroundStyle(statusColor)
                }
            }

            HStack(spacing: TranceSpacing.inner) {
                Button(action: onChoose) {
                    Label(
                        selectedAudioFile?.displayName ?? "Choose Local File",
                        systemImage: selectedAudioFile == nil ? "folder" : "checkmark.circle.fill"
                    )
                    .font(TranceTypography.body)
                    .foregroundStyle(selectedAudioFile == nil ? Color.roseGold : Color.green)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(selectedAudioFile == nil ? .roseGold : .green)

                if canDownload {
                    Button(action: onDownload) {
                        Group {
                            if isDownloading {
                                ProgressView()
                                    .tint(.roseGold)
                            } else {
                                Label("Download", systemImage: "arrow.down.circle")
                                    .font(TranceTypography.body)
                                    .foregroundStyle(Color.roseGold)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.roseGold)
                    .disabled(isDownloading)
                    .accessibilityLabel("Download \(row.track.name) from the publisher")
                }
            }

            if case .possibleDuplicate = row.status, let possibleDuplicate {
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text("Already in your library as “\(possibleDuplicate.displayName)”")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textLight)

                    HStack(spacing: TranceSpacing.inner) {
                        Button("Use Existing", systemImage: "checkmark.circle", action: onUseExisting)
                            .buttonStyle(.borderedProminent)
                            .tint(.roseGold)

                        Button("Keep Both", systemImage: "arrow.down.circle", action: onDownloadAnyway)
                            .buttonStyle(.bordered)
                            .tint(.textLight)
                    }
                    .font(TranceTypography.body)
                    .frame(minHeight: 44)
                }
            }

            if let downloadError {
                Label(downloadError, systemImage: "exclamationmark.triangle.fill")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, TranceSpacing.micro)
        .accessibilityElement(children: .contain)
    }

    private var statusText: String {
        switch row.status {
        case .exact: "Exact match"
        case .probable: "Probable match"
        case .needsReview: "Choose between possible matches"
        case .missing: "Not matched"
        case .manual: "Selected manually"
        case .downloaded: "Downloaded from the publisher"
        case .possibleDuplicate: "You may already have this"
        }
    }

    private var statusIcon: String {
        switch row.status {
        case .exact: "checkmark.seal.fill"
        case .probable: "checkmark.circle.fill"
        case .needsReview: "questionmark.circle.fill"
        case .missing: "exclamationmark.circle.fill"
        case .manual: "hand.tap.fill"
        case .downloaded: "arrow.down.circle.fill"
        case .possibleDuplicate: "doc.on.doc.fill"
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .exact, .manual, .downloaded: .green
        case .probable: .roseGold
        case .needsReview, .possibleDuplicate: .orange
        case .missing: .textLight
        }
    }
}
