// AudioLibraryView+Filtering.swift
// Ilumionate
//

import SwiftUI

extension AudioLibraryView {

    // MARK: - Audio Files Grid

    var audioFilesGrid: some View {
        LazyVStack(spacing: TranceSpacing.cardMargin) {
            if !filteredAudioFiles.isEmpty {
                GlassCard(label: resultsHeaderText) {
                    LazyVStack(spacing: TranceSpacing.card) {
                        ForEach(filteredAudioFiles) { file in
                            AudioFileRow(
                                file: file,
                                audioManager: audioManager,
                                analysisManager: analysisManager,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedFiles.contains(file.id),
                                onPlay: { openPlayer(for: file) },
                                onRename: {
                                    fileToRename = file
                                    newFilename = file.displayName
                                    showingRenameAlert = true
                                },
                                onDelete: { deleteFile(file) },
                                onToggleSelection: { toggleSelection(for: file) },
                                onToggleFavorite: {
                                    toggleFavorite(for: file)
                                },
                                onUpdateRating: { newRating in
                                    updateRating(for: file, rating: newRating)
                                },
                                onDetailedRating: {
                                    showDetailedRatingSheet(for: file)
                                },
                                onAddToPlaylist: {
                                    print("🎵 Add \(file.filename) to playlist")
                                    TranceHaptics.shared.light()
                                }
                            )

                            if file.id != filteredAudioFiles.last?.id {
                                Rectangle()
                                    .fill(Color.glassBorder.opacity(0.3))
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.cardMargin)
            }
        }
    }

    // MARK: - Filtered Audio Files

    var filteredAudioFiles: [AudioFile] {
        let baseFilter = audioFiles.filter { file in
            // Search filter
            let matchesSearch: Bool = {
                if searchText.isEmpty { return true }

                let searchInFilename = file.filename.localizedCaseInsensitiveContains(searchText)
                let searchInTranscription = searchTranscription && (file.transcription?.localizedCaseInsensitiveContains(searchText) == true)

                // Also search in analysis results if available
                let searchInAnalysis = file.analysisResult?.aiSummary.localizedCaseInsensitiveContains(searchText) == true ||
                                     file.analysisResult?.recommendedPreset.localizedCaseInsensitiveContains(searchText) == true

                return searchInFilename || searchInTranscription || searchInAnalysis
            }()

            // Content type filter
            let matchesContentType: Bool = {
                switch contentFilter {
                case .all: return true
                case .hypnosis: return file.analysisResult?.contentType == .hypnosis
                case .meditation: return file.analysisResult?.contentType == .meditation
                case .music: return file.analysisResult?.contentType == .music
                case .guided: return file.analysisResult?.contentType == .guidedImagery
                case .affirmations: return file.analysisResult?.contentType == .affirmations
                case .analyzed: return file.isAnalyzed
                case .unanalyzed: return !file.isAnalyzed
                }
            }()

            // Duration filter
            let matchesDuration: Bool = {
                switch durationFilter {
                case .all: return true
                case .short: return file.duration >= 300 && file.duration < 900 // 5-15 min
                case .medium: return file.duration >= 900 && file.duration < 1800 // 15-30 min
                case .long: return file.duration >= 1800 && file.duration < 3600 // 30-60 min
                case .extended: return file.duration >= 3600 // 60+ min
                }
            }()

            // Trance depth filter (only applicable to analyzed hypnosis files)
            let matchesTranceDeph: Bool = {
                switch tranceDepthFilter {
                case .all: return true
                case .light: return file.analysisResult?.hypnosisMetadata?.estimatedTranceDeph == .light
                case .medium: return file.analysisResult?.hypnosisMetadata?.estimatedTranceDeph == .medium
                case .deep: return file.analysisResult?.hypnosisMetadata?.estimatedTranceDeph == .deep
                case .somnambulism: return file.analysisResult?.hypnosisMetadata?.estimatedTranceDeph == .somnambulism
                }
            }()

            let matchesFavorite = !showFavoritesOnly || file.favorite

            return matchesSearch && matchesContentType && matchesDuration && matchesTranceDeph && matchesFavorite
        }

        return baseFilter.sorted { file1, file2 in
            switch sortOption {
            case .newest:
                return file1.createdDate > file2.createdDate
            case .name:
                return file1.filename.localizedStandardCompare(file2.filename) == .orderedAscending
            case .rating:
                return file1.userRating > file2.userRating
            case .duration:
                return file1.duration < file2.duration
            case .analyzed:
                if file1.isAnalyzed != file2.isAnalyzed {
                    return file1.isAnalyzed
                }
                return file1.createdDate > file2.createdDate
            case .tranceDepth:
                let depth1 = file1.analysisResult?.hypnosisMetadata?.estimatedTranceDeph.rawValue ?? "unknown"
                let depth2 = file2.analysisResult?.hypnosisMetadata?.estimatedTranceDeph.rawValue ?? "unknown"
                let depthOrder = ["deep", "somnambulism", "medium", "light", "unknown"]
                let index1 = depthOrder.firstIndex(of: depth1) ?? depthOrder.count
                let index2 = depthOrder.firstIndex(of: depth2) ?? depthOrder.count
                return index1 < index2
            case .confidence:
                let conf1 = file1.analysisResult?.classificationConfidence?.overallConfidence ?? 0
                let conf2 = file2.analysisResult?.classificationConfidence?.overallConfidence ?? 0
                return conf1 > conf2
            case .lastPlayed:
                let played1 = file1.lastPlayedDate ?? Date.distantPast
                let played2 = file2.lastPlayedDate ?? Date.distantPast
                return played1 > played2
            }
        }
    }

    // MARK: - Results Header

    var resultsHeaderText: String {
        var components: [String] = []

        // Count with smart description
        let count = filteredAudioFiles.count
        let totalCount = audioFiles.count

        if count == totalCount {
            components.append("All Files (\(count))")
        } else {
            components.append("\(count) of \(totalCount) Files")
        }

        // Add active filter descriptions
        var filters: [String] = []

        if contentFilter != .all {
            filters.append(contentFilter.rawValue)
        }

        if durationFilter != .all {
            filters.append(durationFilter.rawValue)
        }

        if tranceDepthFilter != .all {
            filters.append(tranceDepthFilter.rawValue)
        }

        if showFavoritesOnly {
            filters.append("Favorites")
        }

        if !filters.isEmpty {
            components.append("• " + filters.joined(separator: ", "))
        }

        return components.joined(separator: " ")
    }
}
