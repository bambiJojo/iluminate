//
//  AnalysisStatusBar.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/24/26.
//

import SwiftUI

/// Compact status bar showing ongoing analysis progress without blocking the UI
struct AnalysisStatusBar: View {

    let stage: AnalysisStage
    let progress: Double
    let fileName: String
    var queueCount: Int = 0
    var onCancel: () -> Void
    var onCancelAll: (() -> Void)?
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Progress indicator
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(stage.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(stage.title)
                        .font(.subheadline.weight(.medium))

                    if queueCount > 0 {
                        Text("(\(queueCount + 1) files)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Progress percentage
            Text("\(Int(progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            // Cancel buttons
            HStack(spacing: 8) {
                if let onCancelAll = onCancelAll {
                    Button {
                        onCancelAll()
                    } label: {
                        Image(systemName: "xmark.square.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AnalysisStatusBar(
            stage: .transcribing,
            progress: 0.35,
            fileName: "meditation_session.m4a",
            queueCount: 3,
            onCancel: { print("Cancelled") },
            onCancelAll: { print("Cancel All") },
            onTap: { print("Tapped") }
        )

        AnalysisStatusBar(
            stage: .analyzing,
            progress: 0.75,
            fileName: "hypnosis_recording.m4a",
            onCancel: { print("Cancelled") },
            onTap: { print("Tapped") }
        )

        AnalysisStatusBar(
            stage: .complete,
            progress: 1.0,
            fileName: "therapy_audio.m4a",
            onCancel: { print("Cancelled") },
            onTap: { print("Tapped") }
        )
    }
    .padding()
}
