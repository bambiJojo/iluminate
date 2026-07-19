// AudioFileRow.swift
// Ilumionate
//

import SwiftUI

// MARK: - Audio File Row Component

struct AudioFileRow: View {
    let file: AudioFile
    let audioManager: AudioManager
    let analysisManager: AnalysisStateManager
    let isSelectionMode: Bool
    let isSelected: Bool
    let onPlay: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onToggleSelection: () -> Void
    let onToggleFavorite: () -> Void
    let onUpdateRating: (Int) -> Void
    let onDetailedRating: () -> Void
    let onAddToPlaylist: () -> Void

    @State private var hasGeneratedSession = false

    private var isAnalyzing: Bool {
        analysisManager.currentAnalysis?.audioFile.id == file.id
    }

    /// Deterministic waveform samples derived from the file's UUID —
    /// same file always renders the same waveform shape.
    private var waveformSamples: [CGFloat] {
        let bytes = Array(file.id.uuidString.utf8)
        return (0..<20).map { idx in
            let byte = bytes[(idx * 2) % bytes.count]
            return CGFloat(byte % 200 + 30) / 230.0
        }
    }

    /// Tints waveform and badges to the file's content type once analyzed.
    private var waveformColor: Color {
        guard let result = file.analysisResult else { return .roseGold }
        return contentTypeColor(result.contentType)
    }

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            // Waveform thumbnail doubles as the play / selection control.
            Button {
                TranceHaptics.shared.medium()
                if isSelectionMode {
                    onToggleSelection()
                } else {
                    onPlay()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                        .fill(
                            LinearGradient(
                                colors: [waveformColor.opacity(0.18), waveformColor.opacity(0.07)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    if !isSelectionMode {
                        WaveformView(
                            samples: waveformSamples,
                            color: waveformColor,
                            strokeWidth: 1.5
                        )
                        .frame(width: 44, height: 28)
                        .opacity(isAnalyzing ? 0.25 : 0.8)
                    }

                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(waveformColor)
                    } else if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isSelected ? Color.roseGold : Color.roseGold.opacity(0.55))
                    } else {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(waveformColor.opacity(0.9))
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: TranceRadius.thumbnail))
            }
            .buttonStyle(.plain)

            // Title + a single, compact metadata line.
            VStack(alignment: .leading, spacing: 4) {
                Text(file.displayName)
                    .font(TranceTypography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: TranceSpacing.inner) {
                    if !isSelectionMode && file.favorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.roseGold)
                    }

                    if let creator = file.creatorDisplayName {
                        Text(creator)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.roseGold)
                            .lineLimit(1)
                    }

                    Text(file.durationFormatted)
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textSecondary)

                    // One badge — the content type — as the primary "analyzed" signal.
                    if let result = file.analysisResult {
                        HStack(spacing: 4) {
                            Image(systemName: contentTypeIcon(result.contentType))
                                .font(.system(size: 10))
                            Text(result.contentType.displayName)
                        }
                        .font(TranceTypography.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(contentTypeColor(result.contentType).opacity(0.15))
                        .foregroundStyle(contentTypeColor(result.contentType))
                        .clipShape(Capsule())
                    }

                    if hasGeneratedSession {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                            .foregroundStyle(.roseGold)
                    }

                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.roseGold)
                    }

                    Spacer(minLength: 0)
                }
            }

            // Affordance: analyzed files open a detail screen.
            if !isSelectionMode && file.isAnalyzed {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.textLight)
            }
        }
        .contentShape(.rect)
        .contextMenu {
            if !isSelectionMode {
                rowMenu
            }
        }
        .task {
            await checkForGeneratedSession()
        }
        .onChange(of: analysisManager.currentAnalysis?.stage) {
            Task {
                await checkForGeneratedSession()
            }
        }
    }

    // MARK: - Secondary Actions (context menu)

    /// All per-file actions live here. Long-press (or tap-and-hold) reveals them.
    /// A context menu works inside the LazyVStack list, unlike `.swipeActions`
    /// which only functions inside a `List`.
    @ViewBuilder
    private var rowMenu: some View {
        Button {
            onPlay()
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            onToggleFavorite()
        } label: {
            Label(file.favorite ? "Remove Favorite" : "Add Favorite",
                  systemImage: file.favorite ? "heart.slash" : "heart")
        }

        if file.isAnalyzed {
            Menu {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        onUpdateRating(star)
                    } label: {
                        Label("\(star) Star\(star > 1 ? "s" : "")",
                              systemImage: star <= file.userRating ? "star.fill" : "star")
                    }
                }
                if file.userRating > 0 {
                    Button(role: .destructive) {
                        onUpdateRating(0)
                    } label: {
                        Label("Clear Rating", systemImage: "xmark")
                    }
                }
            } label: {
                Label("Rate", systemImage: "star")
            }
        }

        Button {
            onAddToPlaylist()
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }

        Button {
            onRename()
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func checkForGeneratedSession() async {
        hasGeneratedSession = GeneratedSessionStore.shared.exists(for: file)
    }

    // MARK: - Helper Functions for Enhanced Display

    private func contentTypeIcon(_ type: AnalysisResult.ContentType) -> String {
        switch type {
        case .hypnosis:        return "brain.head.profile"
        case .meditation:      return "leaf"
        case .music:           return "music.note"
        case .guidedImagery:   return "figure.mind.and.body"
        case .affirmations:    return "quote.bubble"
        case .eroticHypnosis:  return "flame"
        case .brainwave:       return "waveform.path.ecg"
        case .asmr:            return "ear"
        case .sleepHypnosis:   return "moon.zzz"
        case .unknown:         return "questionmark.circle"
        }
    }

    private func contentTypeColor(_ type: AnalysisResult.ContentType) -> Color {
        switch type {
        case .hypnosis:        return .phaseInduction
        case .meditation:      return .bwTheta
        case .music:           return .bwAlpha
        case .guidedImagery:   return .phaseDeepener
        case .affirmations:    return .warmAccent
        case .eroticHypnosis:  return .roseDeep
        case .brainwave:       return .bwGamma
        case .asmr:            return .warmAccent
        case .sleepHypnosis:   return .bwDelta
        case .unknown:         return .roseGold
        }
    }
}
