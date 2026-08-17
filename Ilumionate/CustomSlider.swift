//
//  CustomSlider.swift
//  Ilumionate
//
//  Extracted from the old MindMachineView. Create's tray uses drag tiles now,
//  but ProfileSettingsView still renders this.
//

import SwiftUI

struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let trackColor: Color
    let thumbColor: Color
    let activeColor: Color

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let thumbPosition = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * geometry.size.width

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(trackColor)
                    .frame(height: 4)

                // Active track
                RoundedRectangle(cornerRadius: 2)
                    .fill(activeColor)
                    .frame(width: thumbPosition, height: 4)
                    .shadow(color: activeColor.opacity(0.6), radius: 6)

                // Thumb
                Circle()
                    .fill(thumbColor)
                    .frame(width: 20, height: 20)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .shadow(color: thumbColor.opacity(0.7), radius: isDragging ? 12 : 8)
                    .offset(x: thumbPosition - 10)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                isDragging = true
                                let percent = gesture.location.x / geometry.size.width
                                let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(max(0, min(1, percent)))
                                value = newValue
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
        }
        .frame(height: 20)
    }
}
