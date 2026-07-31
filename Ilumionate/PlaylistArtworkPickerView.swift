//
//  PlaylistArtworkPickerView.swift
//  Ilumionate
//
//  Gallery of selectable playlist artwork: Auto (content-derived mosaic) plus
//  every trance/hypnosis motif in every colorway.
//

import SwiftUI

struct PlaylistArtworkPickerView: View {
    /// Content types used to preview the Auto option accurately.
    let types: [AudioContentType]
    @Binding var selection: PlaylistArtworkStyle
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 96), spacing: TranceSpacing.list)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: columns, spacing: TranceSpacing.card) {
                        ForEach(PlaylistArtworkStyle.gallery) { style in
                            styleTile(style)
                        }
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.vertical, TranceSpacing.cardMargin)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Artwork")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.roseGold)
                }
            }
        }
    }

    private func styleTile(_ style: PlaylistArtworkStyle) -> some View {
        let isSelected = style == selection

        return Button {
            TranceHaptics.shared.selection()
            selection = style
        } label: {
            VStack(spacing: TranceSpacing.icon) {
                PlaylistArtworkView(
                    types: types,
                    cornerRadius: TranceRadius.thumbnail,
                    iconSize: 24,
                    style: style,
                    motifLineWidth: 2.5
                )
                .frame(height: 96)
                .overlay {
                    RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                        .stroke(isSelected ? Color.roseGold : Color.glassBorder,
                                lineWidth: isSelected ? 2.5 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.roseGold)
                            .background(Circle().fill(Color.bgPrimary))
                            .padding(TranceSpacing.icon)
                    }
                }

                Text(style.displayName)
                    .font(TranceTypography.caption)
                    .foregroundStyle(isSelected ? Color.roseGold : Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    @Previewable @State var selection = PlaylistArtworkStyle.automatic
    return PlaylistArtworkPickerView(types: [.hypnosis, .meditation], selection: $selection)
}
