//
//  AudioScrubber.swift
//  Ilumionate
//
//  Audio progress slider with rose-gold gradient
//

import SwiftUI

struct AudioScrubber: View {
    @Binding var progress: Double  // 0.0–1.0
    let onChanged: ((Double) -> Void)?

    init(progress: Binding<Double>, onChanged: ((Double) -> Void)? = nil) {
        self._progress = progress
        self.onChanged = onChanged
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.roseGold.opacity(0.2))
                    .frame(height: 4)

                // Progress track
                Capsule()
                    .fill(
                        LinearGradient(colors: [.roseGold, .blush],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geometry.size.width * progress, height: 4)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newProgress = min(max(value.location.x / geometry.size.width, 0), 1)
                        progress = newProgress
                        onChanged?(newProgress)
                    }
            )
        }
        .frame(height: 4)
    }
}

// MARK: - Preview

#Preview {
    struct AudioScrubberPreview: View {
        @State private var progress: Double = 0.3

        var body: some View {
            VStack(spacing: TranceSpacing.content) {
                Text("Progress: \(Int(progress * 100))%")
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)

                AudioScrubber(progress: $progress) { newProgress in
                    print("Progress changed to: \(newProgress)")
                }

                HStack {
                    Text("18:24")
                        .font(.system(size: 11))
                        .foregroundColor(.textLight)
                    Spacer()
                    Text("-42:16")
                        .font(.system(size: 11))
                        .foregroundColor(.textLight)
                }
            }
            .padding(TranceSpacing.screen)
            .background(Color.bgPrimary)
        }
    }

    return AudioScrubberPreview()
}