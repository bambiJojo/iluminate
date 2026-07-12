//  CarouselRow.swift
//  Ilumionate
//
//  Shared horizontal shelf for the Reader tab: view-aligned paging with a
//  peek of the next card, matching the Apple Music shelf pattern.

import SwiftUI

struct CarouselRow<Item: Identifiable, Card: View>: View {
    let items: [Item]
    /// Fraction of the container width each card occupies (rest is the peek).
    var cardWidthFraction: CGFloat = 0.78
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
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
