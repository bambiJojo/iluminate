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
            // Waveform thumbnail / selection button
            Button {
                TranceHaptics.shared.medium()
                if isSelectionMode {
                    onToggleSelection()
                } else {
                    onPlay()
                }
            } label: {
                ZStack {
                    // Gradient background tinted by content type
                    RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                        .fill(
                            LinearGradient(
                                colors: [waveformColor.opacity(0.18), waveformColor.opacity(0.07)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Mini waveform (hidden while spinning or selected)
                    if !isSelectionMode {
                        WaveformView(
                            samples: waveformSamples,
                            color: waveformColor,
                            strokeWidth: 1.5
                        )
                        .frame(width: 44, height: 28)
                        .opacity(isAnalyzing ? 0.25 : 0.8)
                    }

                    // Overlay: spinner / checkmark / play icon
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

            // File info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.displayName)
                        .font(TranceTypography.body)
                        .fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    Spacer()

                    // Rating Stars
                    if !isSelectionMode && file.isAnalyzed {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= file.userRating ? "star.fill" : "star")
                                    .font(.caption2)
                                    .foregroundColor(star <= file.userRating ? .roseGold : .textLight)
                                    .onTapGesture {
                                        onUpdateRating(star == file.userRating ? 0 : star)
                                    }
                            }
                        }
                    }

                    // Playlist Add Button
                    if !isSelectionMode {
                        Button {
                            TranceHaptics.shared.light()
                            onAddToPlaylist()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.roseGold)
                        }
                    }
                }

                // Metadata row with heart, duration, and badges
                HStack(spacing: TranceSpacing.list) {
                    // Heart icon next to duration
                    if !isSelectionMode {
                        Image(systemName: file.favorite ? "heart.fill" : "heart")
                            .font(.caption)
                            .foregroundColor(file.favorite ? .roseGold : .textLight)
                    }

                    Text(file.durationFormatted)
                        .font(TranceTypography.caption)
                        .foregroundColor(.textSecondary)

                    // Analysis status badges
                    HStack(spacing: TranceSpacing.icon) {
                        if file.isAnalyzed {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundColor(.phaseInduction)
                        }

                        if hasGeneratedSession {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundColor(.roseGold)
                        }

                        if isAnalyzing {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.roseGold)
                        }
                    }
                }

                // Enhanced Content Badges (without file size)
                if let result = file.analysisResult {
                    HStack(spacing: TranceSpacing.inner) {
                        // Content Type Badge
                        HStack(spacing: 4) {
                            Image(systemName: contentTypeIcon(result.contentType))
                                .font(.system(size: 10))
                            Text(result.contentType.rawValue.capitalized)
                        }
                        .font(TranceTypography.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(contentTypeColor(result.contentType).opacity(0.15))
                        .foregroundColor(contentTypeColor(result.contentType))
                        .clipShape(Capsule())

                        // Trance Depth Badge (for hypnosis)
                        if result.contentType == .hypnosis,
                           let depth = result.hypnosisMetadata?.estimatedTranceDeph {
                            HStack(spacing: 2) {
                                Image(systemName: tranceDepthIcon(depth))
                                    .font(.system(size: 10))
                                Text(depth.rawValue.capitalized)
                            }
                            .font(TranceTypography.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tranceDepthColor(depth).opacity(0.15))
                            .foregroundColor(tranceDepthColor(depth))
                            .clipShape(Capsule())
                        }

                        // AI Confidence Indicator
                        if let confidence = result.classificationConfidence?.overallConfidence {
                            HStack(spacing: 2) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                                Text("\(Int(confidence * 100))%")
                            }
                            .font(TranceTypography.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(confidenceColor(confidence).opacity(0.15))
                            .foregroundColor(confidenceColor(confidence))
                            .clipShape(Capsule())
                        }

                        Spacer()
                    }
                }

            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .leading) {
            if !isSelectionMode {
                // Delete action (swipe from left)
                Button(role: .destructive) {
                    TranceHaptics.shared.medium()
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash.fill")
                }
                .tint(.red)
            }
        }
        .swipeActions(edge: .trailing) {
            if !isSelectionMode {
                // Favorite action (swipe from right)
                Button {
                    TranceHaptics.shared.light()
                    onToggleFavorite()
                } label: {
                    Label(file.favorite ? "Unfavorite" : "Favorite",
                          systemImage: file.favorite ? "heart.slash.fill" : "heart.fill")
                }
                .tint(file.favorite ? .gray : .roseGold)

                // Rename action (swipe from right)
                Button {
                    TranceHaptics.shared.light()
                    onRename()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
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

    private func checkForGeneratedSession() async {
        let fileManager = FileManager.default
        let documentsURL = URL.documentsDirectory
        let sessionsURL = documentsURL.appendingPathComponent("GeneratedSessions", isDirectory: true)

        let baseName = file.filename
            .replacing(".mp3", with: "")
            .replacing(".m4a", with: "")
            .replacing(".wav", with: "")
        let filename = "\(baseName)_session.json"
        let fileURL = sessionsURL.appendingPathComponent(filename)

        hasGeneratedSession = fileManager.fileExists(atPath: fileURL.path)
    }

    // MARK: - Helper Functions for Enhanced Display

    private func contentTypeIcon(_ type: AnalysisResult.ContentType) -> String {
        switch type {
        case .hypnosis: return "brain.head.profile"
        case .meditation: return "leaf"
        case .music: return "music.note"
        case .guidedImagery: return "figure.mind.and.body"
        case .affirmations: return "quote.bubble"
        case .unknown: return "questionmark.circle"
        }
    }

    private func contentTypeColor(_ type: AnalysisResult.ContentType) -> Color {
        switch type {
        case .hypnosis:      return .phaseInduction   // teal
        case .meditation:    return .bwTheta           // soft purple
        case .music:         return .bwAlpha           // rose
        case .guidedImagery: return .phaseDeepener     // deep purple
        case .affirmations:  return .warmAccent        // warm amber
        case .unknown:       return .roseGold
        }
    }

    private func tranceDepthIcon(_ depth: HypnosisMetadata.TranceDeph) -> String {
        switch depth {
        case .light: return "circle"
        case .medium: return "circle.fill"
        case .deep: return "circles.hexagongrid.fill"
        case .somnambulism: return "brain"
        }
    }

    private func tranceDepthColor(_ depth: HypnosisMetadata.TranceDeph) -> Color {
        switch depth {
        case .light: return .cyan
        case .medium: return .blue
        case .deep: return .indigo
        case .somnambulism: return .purple
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .yellow
        default: return .orange
        }
    }

    private func ratingIndicator(_ icon: String, value: Int, color: Color) -> some View {
        HStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(color)
            Text("\(value)")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(color)
        }
    }
}
