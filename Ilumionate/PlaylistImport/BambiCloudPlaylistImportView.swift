import SwiftUI

enum PlaylistImportContentRoute: Equatable {
    case linkEntry
    case review

    static func resolve(hasPlan: Bool) -> Self {
        return hasPlan ? .review : .linkEntry
    }
}

struct BambiCloudPlaylistImportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: BambiCloudPlaylistImportViewModel
    @State private var selectingRow: BambiCloudPlaylistImportPlan.Row?

    private let onImport: (Playlist) -> Void

    init(
        audioFiles: [AudioFile],
        initialLink: String? = nil,
        onImport: @escaping (Playlist) -> Void
    ) {
        let model = BambiCloudPlaylistImportViewModel(
            availableAudioFiles: audioFiles
        )
        if let initialLink {
            model.linkText = initialLink
        }
        _model = State(initialValue: model)
        self.onImport = onImport
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Group {
                switch PlaylistImportContentRoute.resolve(
                    hasPlan: model.plan != nil
                ) {
                case .linkEntry:
                    BambiCloudPlaylistLinkEntryView(model: model)

                case .review:
                    if let plan = model.plan {
                        BambiCloudPlaylistReviewView(
                            plan: plan,
                            audioFiles: model.availableAudioFiles,
                            isDownloading: model.isDownloading,
                            downloadError: { model.downloadErrors[$0] },
                            onChoose: { selectingRow = $0 },
                            onDownload: { row in
                                Task { await model.requestDownload(of: row) }
                            },
                            onUseExisting: { row, existingID in
                                model.select(audioFileID: existingID, forRow: row.id)
                            },
                            onDownloadAnyway: { row in
                                Task { await model.downloadAnyway(row) }
                            },
                            onDownloadAll: {
                                Task { await model.requestDownloadOfAllMissingTracks() }
                            },
                            onStartOver: model.startOver
                        )
                    }
                }
            }
            .navigationTitle(
                model.plan == nil ? "Import Playlist" : "Review Matches"
            )
            .platformInlineNavigationTitle()
            .task {
                // A link picked in the browser is already known-good, so match
                // it immediately instead of re-showing the entry form.
                if model.plan == nil, model.canLoad {
                    await model.loadPlaylist()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }

                if model.plan != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(importButtonTitle, action: importPlaylist)
                            .disabled(!model.canImport)
                    }
                }
            }
            .alert(
                item: $model.pendingDownload
            ) { pending in
                Alert(
                    title: Text(pending.title),
                    message: Text(pending.message),
                    primaryButton: .default(Text("Download")) {
                        Task { await model.confirmDownload(pending) }
                    },
                    secondaryButton: .cancel {
                        model.cancelPendingDownload()
                    }
                )
            }
            .sheet(item: $selectingRow) { row in
                // Read the live row back by id: the captured copy is a snapshot
                // from when the sheet was presented.
                let current = model.plan?.rows.first { $0.id == row.id } ?? row
                LocalAudioMatchPicker(
                    track: current.track,
                    audioFiles: model.availableAudioFiles,
                    suggestedAudioFileIDs: current.suggestedAudioFileIDs,
                    selectedAudioFileID: current.selectedAudioFileID,
                    onSelect: { audioFileID in
                        model.select(audioFileID: audioFileID, forRow: row.id)
                        selectingRow = nil
                    }
                )
            }
        }
    }

    private var importButtonTitle: String {
        "Import \(model.plan?.matchedCount ?? 0)"
    }

    private func importPlaylist() {
        guard let playlist = model.makePlaylist() else {
            return
        }

        onImport(playlist)
        TranceHaptics.shared.medium()
        dismiss()
    }
}
