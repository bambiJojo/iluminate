//  CreateTintSheet.swift
//  Ilumionate
//
//  The Colour tile's swatch grid, with the custom picker behind it.
//
//  A sheet rather than tap-to-cycle-plus-long-press: PlayerControlTile is
//  "either tappable or draggable, never both, which keeps gesture arbitration
//  out of the picture entirely", and a third gesture on one tile would put it
//  straight back in. The sheet also gives the custom picker somewhere to live.

import SwiftUI

struct CreateTintSheet: View {
    @Binding var tint: VisualTint
    @Environment(\.dismiss) private var dismiss

    @State private var customColor: Color = VisualTint.default.color

    private let columns = Array(repeating: GridItem(.flexible()), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                    LazyVGrid(columns: columns, spacing: TranceSpacing.cardMargin) {
                        ForEach(VisualTint.palette, id: \.self) { swatch in
                            swatchButton(swatch)
                        }
                    }

                    Divider().background(Color.glassBorder)

                    ColorPicker(
                        "Custom colour",
                        selection: $customColor,
                        supportsOpacity: false
                    )
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textPrimary)
                    .onChange(of: customColor) { _, newValue in
                        guard let hex = newValue.hexString else { return }
                        tint = .custom(hex)
                        TranceHaptics.shared.selection()
                    }

                    Text("Very dark colours are lifted so the field stays visible.")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(TranceSpacing.screen)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Colour")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            // Open the picker on whatever is already selected, so nudging it
            // does not jump the field to an unrelated hue.
            customColor = tint.color
        }
    }

    private func swatchButton(_ swatch: VisualTint) -> some View {
        Button {
            tint = swatch
            TranceHaptics.shared.selection()
        } label: {
            VStack(spacing: TranceSpacing.micro) {
                Circle()
                    .fill(swatch.color)
                    .frame(height: 52)
                    .overlay {
                        Circle().stroke(
                            tint == swatch ? Color.textPrimary : Color.glassBorder,
                            lineWidth: tint == swatch ? 2 : 1
                        )
                    }
                Text(swatch.displayName)
                    .font(TranceTypography.caption)
                    .foregroundStyle(
                        tint == swatch ? Color.textPrimary : Color.textSecondary
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.displayName)
        .accessibilityAddTraits(tint == swatch ? [.isButton, .isSelected] : .isButton)
    }
}
