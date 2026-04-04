//
//  SyncToggle.swift
//  Ilumionate
//
//  Custom toggle with rose-gold styling for Mind Machine sync
//

import SwiftUI

struct SyncToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Sync Mind Machine", isOn: $isOn)
            .toggleStyle(RoseToggleStyle())
    }
}

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
    struct SyncTogglePreview: View {
        @State private var isSync1 = false
        @State private var isSync2 = true

        var body: some View {
            VStack(spacing: TranceSpacing.cardMargin) {
                GlassCard(label: "Sync Options") {
                    VStack(spacing: TranceSpacing.list) {
                        SyncToggle(isOn: $isSync1)
                        SyncToggle(isOn: $isSync2)
                    }
                }
            }
            .padding(TranceSpacing.screen)
            .background(Color.bgPrimary)
        }
    }

    return SyncTogglePreview()
}