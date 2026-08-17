//
//  HomeDoorsView.swift
//  Ilumionate
//
//  The four doors, as equal-weight quadrants.
//
//  Equal size is the point: these are four things people can like, and sizing
//  one larger would assert a favourite the product does not have. Glass rather
//  than flat fill so the aurora behind stays visible.
//

import SwiftUI

struct HomeDoorsView: View {
    let onSelect: (HomeDoor) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: TranceSpacing.list), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: TranceSpacing.list) {
            ForEach(HomeDoor.allCases) { door in
                HomeDoorTile(
                    door: door,
                    isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
                ) {
                    onSelect(door)
                }
            }
        }
    }
}

private struct HomeDoorTile: View {
    let door: HomeDoor
    /// At accessibility sizes the grid drops to one column, where a square
    /// would be a full-width block and the subtitle would need to wrap out of
    /// it. Height goes back to hugging the text there.
    let isAccessibilitySize: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                Image(systemName: door.systemImage)
                    .font(.title2)
                    .foregroundStyle(door.tint)

                Spacer(minLength: TranceSpacing.inner)

                Text(door.title)
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(Color.textPrimary)

                Text(door.subtitle)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TranceSpacing.card)
            .modifier(SquareWhenCompact(enabled: !isAccessibilitySize))
            .background(door.tint.opacity(0.10), in: .rect(cornerRadius: TranceRadius.glassCard))
            .liminalGlass(.roundedRect(cornerRadius: TranceRadius.glassCard))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(door.title)
        .accessibilityHint(door.subtitle)
    }
}

/// Keeps the four doors square so they read as quadrants of one field rather
/// than as four cards of arbitrary height. Without this the tile's `Spacer`
/// expands to whatever the scroll view offers and each door becomes a tall,
/// mostly empty box.
private struct SquareWhenCompact: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.aspectRatio(1, contentMode: .fit)
        } else {
            content
        }
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        HomeDoorsView { _ in }
            .padding(TranceSpacing.screen)
    }
}
