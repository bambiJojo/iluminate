//  CarouselRow.swift
//  Ilumionate
//
//  Shared horizontal shelf used by the Reader and Library tabs: view-aligned
//  paging with a peek of the next card, matching the Apple Music shelf pattern.

import SwiftUI

struct CarouselRow<Item: Identifiable, Card: View>: View {
    let items: [Item]
    /// Fraction of the container width each card occupies when the shelf holds
    /// more than one item (the remainder is the peek of the next card).
    var cardWidthFraction: CGFloat = 0.86
    @ViewBuilder let card: (Item) -> Card

    /// A lone card fills the width — there is nothing to peek toward, so a
    /// partial-width card would just leave dead space to its right.
    private var isSingle: Bool { items.count == 1 }

    var body: some View {
        if isSingle, let item = items.first {
            card(item)
                .padding(.horizontal, TranceSpacing.screen)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: TranceSpacing.list) {
                    ForEach(items) { item in
                        card(item)
                            .containerRelativeFrame(.horizontal) { length, _ in
                                length * cardWidthFraction
                            }
                            .scrollTransition(.interactive) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                    .opacity(phase.isIdentity ? 1 : 0.65)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, TranceSpacing.screen, for: .scrollContent)
        }
    }
}
