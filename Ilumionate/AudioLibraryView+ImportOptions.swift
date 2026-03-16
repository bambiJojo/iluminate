// AudioLibraryView+ImportOptions.swift
// Ilumionate
//

import SwiftUI

extension AudioLibraryView {

    // MARK: - Import Options Section (shown in confirmation dialog via toolbar + button)
    // Full import card kept here for potential future "onboarding import" use.

    var importOptionsSection: some View {
        GlassCard(label: "Add Audio") {
            VStack(spacing: TranceSpacing.inner) {
                // --- Import from File (Primary) ---
                Button {
                    TranceHaptics.shared.light()
                    showingImporter = true
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                            .frame(width: 28)
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import from File")
                                .font(TranceTypography.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Text("Choose MP3, M4A, or WAV files")
                                .font(TranceTypography.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, TranceSpacing.card)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                    .shadow(color: Color.roseGold.opacity(0.30), radius: 8, x: 0, y: 4)
                }

                // --- Import from Web (Secondary) ---
                Button {
                    TranceHaptics.shared.light()
                    showingURLDownloader = true
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Group {
                            if isDownloadingURL {
                                ProgressView()
                                    .tint(.roseGold)
                            } else {
                                Image(systemName: "link.icloud.fill")
                                    .font(.title2)
                            }
                        }
                        .frame(width: 28)
                        .foregroundColor(.roseGold)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isDownloadingURL ? "Downloading..." : "Import from Web")
                                .font(TranceTypography.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.textPrimary)

                            Text(isDownloadingURL ? "Saving to your library..." : "Paste a link to an audio file")
                                .font(TranceTypography.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textLight)
                    }
                    .padding(.horizontal, TranceSpacing.card)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        RoundedRectangle(cornerRadius: TranceRadius.button)
                            .fill(Color.roseGold.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: TranceRadius.button)
                                    .strokeBorder(Color.roseGold.opacity(0.35), lineWidth: 1)
                            )
                    )
                }
                .disabled(isDownloadingURL)

                // --- Browse the Web (Tertiary) ---
                Button {
                    TranceHaptics.shared.light()
                    showingBrowser = true
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Image(systemName: "safari.fill")
                            .font(.title2)
                            .frame(width: 28)
                            .foregroundColor(.textSecondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Browse the Web")
                                .font(TranceTypography.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.textPrimary)

                            Text("Find & download audio in-app")
                                .font(TranceTypography.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textLight)
                    }
                    .padding(.horizontal, TranceSpacing.card)
                    .padding(.vertical, TranceSpacing.card)
                    .background(
                        RoundedRectangle(cornerRadius: TranceRadius.button)
                            .fill(Color.glassBorder.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: TranceRadius.button)
                                    .strokeBorder(Color.glassBorder.opacity(0.35), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.cardMargin)
    }
}
