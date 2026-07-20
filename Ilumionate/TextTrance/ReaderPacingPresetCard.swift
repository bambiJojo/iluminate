import SwiftUI

struct ReaderPacingPresetCard: View {
    let selection: ReaderPacingPreset
    let onSelect: (ReaderPacingPreset) -> Void

    var body: some View {
        LiminalCard(label: "Pacing") {
            VStack(spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.inner) {
                    ForEach(ReaderPacingPreset.allCases) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            Label(
                                preset.title,
                                systemImage: selection == preset ? "checkmark" : "circle"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(selection == preset ? Color.roseGold : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                    }
                }

                Text(selection.detail)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
