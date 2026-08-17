//
//  DiscoveredAudioSheet.swift
//  Ilumionate
//
//  The audio a page turned out to be referencing, offered for download.
//
//  Only links the downloader can actually fetch reach this list — `blob:` URLs
//  and streaming manifests are dropped during discovery, because a row that
//  always fails is worse than a row that was never shown.
//

import SwiftUI

struct DiscoveredAudioSheet: View {
    let links: [DiscoveredAudioLink]
    let onSelect: (DiscoveredAudioLink) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(links) { link in
                        Button {
                            TranceHaptics.shared.light()
                            onSelect(link)
                        } label: {
                            row(for: link)
                        }
                        .buttonStyle(.plain)

                        if link.id != links.last?.id {
                            Divider()
                                .background(Color.glassBorder.opacity(0.25))
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(Color.bgCard)
                .clipShape(.rect(cornerRadius: TranceRadius.glassCard))
                .overlay {
                    RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                        .strokeBorder(Color.glassBorder, lineWidth: 1)
                }
                .padding(TranceSpacing.screen)
            }
            .background(Color.bgPrimary)
            .navigationTitle(title)
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.roseGold)
                }
            }
        }
    }

    private var title: String {
        links.count == 1 ? "1 Audio File" : "\(links.count) Audio Files"
    }

    private func row(for link: DiscoveredAudioLink) -> some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 22))
                .foregroundStyle(Color.roseGold)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(link.url.lastPathComponent)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textLight)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(TranceSpacing.card)
        .contentShape(.rect)
    }
}
