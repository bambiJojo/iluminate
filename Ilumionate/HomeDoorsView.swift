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
                HomeDoorTile(door: door) { onSelect(door) }
            }
        }
    }
}

private struct HomeDoorTile: View {
    let door: HomeDoor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                Image(systemName: door.systemImage)
                    .font(.title2)
                    .foregroundStyle(door.tint)

                Spacer(minLength: TranceSpacing.content)

                Text(door.title)
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(Color.textPrimary)

                Text(door.subtitle)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .padding(TranceSpacing.card)
            .background(door.tint.opacity(0.10), in: .rect(cornerRadius: TranceRadius.glassCard))
            .liminalGlass(.roundedRect(cornerRadius: TranceRadius.glassCard))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(door.title)
        .accessibilityHint(door.subtitle)
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        HomeDoorsView { _ in }
            .padding(TranceSpacing.screen)
    }
}
