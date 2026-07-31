//
//  LibraryFileResultRow.swift
//  Ilumionate
//
//  The one dense audio row used by every flat file list — Library search
//  results and the pushed browse screen. Tapping the row plays; the trailing
//  info control opens the session's detail screen.
//

import SwiftUI

struct LibraryFileResultRow: View {
    let file: AudioFile
    let onPlay: () -> Void
    let onOpenInfo: () -> Void
    var onAddToPlaylist: (() -> Void)?
    var onAnalyze: (() -> Void)?

    var body: some View {
        HStack(spacing: TranceSpacing.inner) {
            Button(action: onPlay) {
                HStack(spacing: TranceSpacing.list) {
                    SessionGlowDot(contentType: file.analysisResult?.contentType, size: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.displayName)
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: TranceSpacing.icon) {
                            if let creator = file.creatorDisplayName {
                                Text(creator)
                                    .font(TranceTypography.caption)
                                    .foregroundStyle(Color.roseGold)
                                    .lineLimit(1)
                            }

                            Text(file.durationFormatted)
                                .font(TranceTypography.caption)
                                .foregroundStyle(Color.textLight)

                            if file.isAnalyzed {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.roseGold)
                            }

                            if file.favorite {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(hex: "E85D75"))
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(file.displayName)")

            Button(action: onOpenInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.textLight)
                    .frame(width: 32, height: 32)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(file.displayName)")
        }
        .padding(.vertical, TranceSpacing.inner)
        .contextMenu {
            Button("Play", systemImage: "play.fill", action: onPlay)
            Button("Session Info", systemImage: "info.circle", action: onOpenInfo)
            if let onAddToPlaylist {
                Button("Add to Playlist", systemImage: "plus", action: onAddToPlaylist)
            }
            if let onAnalyze {
                Button("Analyze", systemImage: "waveform", action: onAnalyze)
            }
        }
    }
}

/// Hairline separator between dense rows, inset past the glow dot.
struct LibraryRowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.glassBorder.opacity(0.3))
            .frame(height: 1)
            .padding(.leading, 46)
    }
}
