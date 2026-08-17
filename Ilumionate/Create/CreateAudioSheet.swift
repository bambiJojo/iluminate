//  CreateAudioSheet.swift
//  Ilumionate
//
//  What rides along with a wordless Visual Field: an optional track from the
//  library, and optional binaural beats. Both are independent, and silence is a
//  valid configured state rather than an unconfigured one.
//
//  A sheet rather than tiles because the tray is fixed at six and every slot is
//  already a visual knob. Audio is not a property of the visual, so it does not
//  belong in that row.

import SwiftUI

struct CreateAudioSheet: View {
    @Binding var track: AudioFile?
    @Binding var binaural: BinauralSettings
    @Environment(\.dismiss) private var dismiss

    @State private var files: [AudioFile] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                Section("Track") {
                    trackRow(nil, title: "No audio", subtitle: "Silence")
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading library…")
                                .font(TranceTypography.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else if files.isEmpty {
                        Text("No audio in your library yet.")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        ForEach(files) { file in
                            trackRow(file, title: file.displayName, subtitle: nil)
                        }
                    }
                }

                Section("Binaural beats") {
                    Toggle("Enable", isOn: $binaural.enabled)
                        .tint(.roseGold)

                    if binaural.enabled {
                        Label("Best experienced with headphones", systemImage: "headphones")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.roseGold.opacity(0.85))

                        slider(
                            "Beat",
                            value: $binaural.beatFrequency,
                            range: 0.5...40,
                            format: { "\($0.formatted(.number.precision(.fractionLength(1)))) Hz" }
                        )
                        slider(
                            "Carrier",
                            value: $binaural.carrier,
                            range: 100...400,
                            format: { "\(Int($0)) Hz" }
                        )
                        slider(
                            "Volume",
                            value: $binaural.volume,
                            range: 0...1,
                            format: { $0.formatted(.percent.precision(.fractionLength(0))) }
                        )
                    }
                }
            }
            .navigationTitle("Audio")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            files = await AudioLibraryStore.loadRepairingStoredFiles()
            isLoading = false
        }
    }

    private func trackRow(_ file: AudioFile?, title: String, subtitle: String?) -> some View {
        Button {
            track = file
            TranceHaptics.shared.selection()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
                if track?.id == file?.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.roseGold)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(track?.id == file?.id ? [.isButton, .isSelected] : .isButton)
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .tint(.roseGold)
        }
    }
}
