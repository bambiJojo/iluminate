//
//  UndoDeleteBanner.swift
//  Ilumionate
//

import SwiftUI

/// Transient confirmation that a delete happened, with a way back.
/// Presentation only — the caller owns the timer and the undo action.
struct UndoDeleteBanner: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: "trash")
                .font(.callout)
                .foregroundStyle(.textSecondary)

            Text(message)
                .font(TranceTypography.caption)
                .foregroundStyle(.textPrimary)
                .lineLimit(1)

            Spacer(minLength: TranceSpacing.inner)

            Button("Undo", action: onUndo)
                .font(TranceTypography.caption)
                .bold()
                .foregroundStyle(.roseGold)

            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(.textLight)
        }
        .padding(.horizontal, TranceSpacing.card)
        .padding(.vertical, TranceSpacing.list)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: TranceRadius.thumbnail))
        .overlay(
            RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                .strokeBorder(Color.glassBorder.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, TranceSpacing.screen)
    }
}

#Preview {
    ZStack {
        Color.bgPrimary.ignoresSafeArea()
        UndoDeleteBanner(message: "Deleted “Deep Rest”", onUndo: {}, onDismiss: {})
    }
}
