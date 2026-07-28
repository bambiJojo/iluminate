//
//  RoseToggleStyle.swift
//  Ilumionate
//
//  Shared rose-gold toggle styling used across settings and player surfaces.
//

import SwiftUI

struct RoseToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .font(.subheadline)
                .foregroundStyle(.textPrimary)
            Spacer()
            Button {
                TranceHaptics.shared.light()
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? Color.roseGold : Color.glassBorder)
                    .frame(width: 46, height: 26)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 2)
                            .padding(3)
                    }
                    .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Preview

#Preview {
    struct RoseTogglePreview: View {
        @State private var isOn1 = false
        @State private var isOn2 = true

        var body: some View {
            VStack(spacing: TranceSpacing.cardMargin) {
                GlassCard(label: "Toggles") {
                    VStack(spacing: TranceSpacing.list) {
                        Toggle("Off by default", isOn: $isOn1)
                            .toggleStyle(RoseToggleStyle())
                        Toggle("On by default", isOn: $isOn2)
                            .toggleStyle(RoseToggleStyle())
                    }
                }
            }
            .padding(TranceSpacing.screen)
            .background(Color.bgPrimary)
        }
    }

    return RoseTogglePreview()
}
