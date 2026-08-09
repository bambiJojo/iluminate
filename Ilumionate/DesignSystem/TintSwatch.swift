//
//  TintSwatch.swift
//  Ilumionate
//
//  One colour circle in a tint picker. Shared by the Visual Field tint sheet
//  and the flash colour sheet so the two pickers cannot drift apart.
//

import SwiftUI

struct TintSwatch: View {
    let color: Color
    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(
        tint: VisualTint,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.color = tint.color
        self.title = tint.displayName
        self.isSelected = isSelected
        self.action = action
    }

    init(
        color: Color,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.color = color
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: TranceSpacing.micro) {
                Circle()
                    .fill(color)
                    .frame(height: 52)
                    .overlay {
                        Circle().stroke(
                            isSelected ? Color.textPrimary : Color.glassBorder,
                            lineWidth: isSelected ? 2 : 1
                        )
                    }
                Text(title)
                    .font(TranceTypography.caption)
                    .foregroundStyle(
                        isSelected ? Color.textPrimary : Color.textSecondary
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
