//
//  FlashTintSheet.swift
//  Ilumionate
//
//  Picks the colour the flash field renders with.
//
//  "Match Session" leads because it is the default and the only option that
//  respects a generated session's own warmth curve. Everything after it is an
//  override that holds one colour for the whole session.
//

import SwiftUI

struct FlashTintSheet: View {
    @Binding var selection: FlashTint

    /// The colour temperature the "Match Session" swatch previews. Sessions
    /// vary, so this is representative rather than authoritative.
    var previewColorTemperature: Int = 3000

    @Environment(\.dismiss) private var dismiss

    @State private var customColor: Color = VisualTint.default.color

    private let columns = Array(repeating: GridItem(.flexible()), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                    LazyVGrid(columns: columns, spacing: TranceSpacing.cardMargin) {
                        TintSwatch(
                            color: Color.fromKelvin(previewColorTemperature),
                            title: "Match Session",
                            isSelected: selection == .matchSession
                        ) {
                            selection = .matchSession
                            TranceHaptics.shared.selection()
                        }

                        ForEach(VisualTint.palette, id: \.self) { swatch in
                            TintSwatch(
                                tint: swatch,
                                isSelected: selection == .tint(swatch)
                            ) {
                                selection = .tint(swatch)
                                TranceHaptics.shared.selection()
                            }
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
                        selection = .tint(.custom(hex))
                        TranceHaptics.shared.selection()
                    }

                    Text(
                        "Match Session follows the warmth the session was built "
                        + "with. Any other colour holds for the whole session."
                    )
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(TranceSpacing.screen)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Flash Colour")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            // Open the picker on the current choice so nudging it does not
            // jump to an unrelated hue.
            customColor = selection.overrideTint?.color
                ?? Color.fromKelvin(previewColorTemperature)
        }
    }
}
