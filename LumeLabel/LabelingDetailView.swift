//
//  LabelingDetailView.swift
//  LumeLabel
//
//  Main labeling workspace. Plays an audio file and lets the labeler mark
//  phase boundaries in real time using keyboard shortcuts 1–7.
//
//  Keyboard shortcuts:
//    1–7     Mark phase start at current playhead position
//    Space   Play / Pause
//    ←  →   Seek ±10 seconds
//    ⌘S     Save
//

import SwiftUI
import AVFoundation

@MainActor
struct LabelingDetailView: View {

    @Environment(TrainingCorpusManager.self) private var corpus
    @State var file: LabeledFile

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var positionTask: Task<Void, Never>?

    private let phases: [HypnosisMetadata.Phase] = [
        .preTalk, .induction, .deepening, .therapy,
        .suggestions, .conditioning, .emergence
    ]

    var body: some View {
        VStack(spacing: 0) {
            phaseTimeline
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            Divider()

            transportBar
                .padding()

            Divider()

            HStack(alignment: .top, spacing: 0) {
                phaseButtons
                    .padding()
                    .frame(width: 180)

                Divider()

                phaseListPanel
                    .padding()
            }
            .frame(minHeight: 220)

            Divider()

            metadataBar
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .navigationTitle(file.audioFilename)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") { saveFile() }
                    .keyboardShortcut("s")
            }
            ToolbarItem {
                statusBadge
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { cleanup() }
    }

    // MARK: - Phase Timeline

    private var phaseTimeline: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .underPageBackgroundColor))

                ForEach(file.phases) { phase in
                    let startFrac = phase.startTime / max(file.audioDuration, 1)
                    let widthFrac = (phase.endTime - phase.startTime) / max(file.audioDuration, 1)
                    let blockWidth = max(2, geo.size.width * widthFrac)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(phaseColor(phase.phase).opacity(0.75))
                        .frame(width: blockWidth)
                        .offset(x: geo.size.width * startFrac)
                        .overlay {
                            if blockWidth > 44 {
                                Text(phase.phase.displayName)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                }

                // Playhead
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2)
                    .offset(x: (currentTime / max(file.audioDuration, 1)) * geo.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { location in
                let newTime = max(0, min(file.audioDuration, location.x / geo.size.width * file.audioDuration))
                seek(to: newTime)
            }
        }
        .frame(height: 48)
    }

    // MARK: - Transport

    private var transportBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text(formatTime(currentTime))
                    .monospacedDigit()
                    .font(.callout)
                Spacer()
                Text(formatTime(file.audioDuration))
                    .monospacedDigit()
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Slider(value: $currentTime, in: 0...max(file.audioDuration, 1)) { editing in
                if !editing { seek(to: currentTime) }
            }

            HStack(spacing: 20) {
                Button("Back 10s", systemImage: "gobackward.10") { seekRelative(-10) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.leftArrow, modifiers: [])

                Button(isPlaying ? "Pause" : "Play",
                       systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    togglePlayback()
                }
                .font(.title2)
                .keyboardShortcut(KeyEquivalent(" "), modifiers: [])

                Button("Forward 10s", systemImage: "goforward.10") { seekRelative(10) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Phase Buttons

    private var phaseButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mark phase at playhead")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(Array(phases.enumerated()), id: \.element) { index, phase in
                Button {
                    markPhaseStart(phase)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 12, alignment: .trailing)
                        Circle()
                            .fill(phaseColor(phase))
                            .frame(width: 8, height: 8)
                        Text(phase.displayName)
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
            }

            Spacer()

            Button("Clear All Phases", role: .destructive) {
                file.phases.removeAll()
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    // MARK: - Phase List

    private var phaseListPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phases (\(file.phases.count))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if file.phases.isEmpty {
                Text("No phases marked yet.\nPlay the audio and press 1–7 at each phase boundary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(file.phases.enumerated()), id: \.element.id) { index, phase in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(phaseColor(phase.phase))
                                    .frame(width: 8, height: 8)
                                Text(phase.phase.displayName)
                                    .bold()
                                    .font(.callout)
                                Spacer()
                                Text("\(formatTime(phase.startTime)) – \(formatTime(phase.endTime))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Button("Remove", systemImage: "minus.circle") {
                                    file.phases.remove(at: index)
                                }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 5)
                            if index < file.phases.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Metadata

    private var metadataBar: some View {
        HStack(spacing: 16) {
            Picker("Type", selection: $file.expectedContentType) {
                ForEach(AnalysisResult.ContentType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 160)

            Menu {
                Button("Delta/Theta  0.5–6 Hz")  { file.expectedFrequencyBand = .init(lower: 0.5, upper: 6.0) }
                Button("Theta  4–8 Hz")          { file.expectedFrequencyBand = .init(lower: 4.0, upper: 8.0) }
                Button("Hypnosis  0.5–10 Hz")    { file.expectedFrequencyBand = .init(lower: 0.5, upper: 10.0) }
                Button("Low Alpha  6–8 Hz")      { file.expectedFrequencyBand = .init(lower: 6.0, upper: 8.0) }
                Button("Alpha  8–12 Hz")         { file.expectedFrequencyBand = .init(lower: 8.0, upper: 12.0) }
                Button("Upper Alpha  9–11 Hz")   { file.expectedFrequencyBand = .init(lower: 9.0, upper: 11.0) }
                Button("SMR/Beta  12–18 Hz")     { file.expectedFrequencyBand = .init(lower: 12.0, upper: 18.0) }
            } label: {
                Label(
                    "\(file.expectedFrequencyBand.lower, format: .number.precision(.fractionLength(1)))–"
                    + "\(file.expectedFrequencyBand.upper, format: .number.precision(.fractionLength(1))) Hz",
                    systemImage: "waveform"
                )
            }

            TextField("Notes…", text: $file.labelerNotes)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        let (label, color): (String, Color) = switch file.status {
        case .unlabeled: ("Unlabeled", .secondary)
        case .rough:     ("Rough", .orange)
        case .refined:   ("Refined", .green)
        }
        return Text(label)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Playback

    private func setupPlayer() {
        let url = corpus.audioURL(for: file)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
    }

    private func cleanup() {
        positionTask?.cancel()
        player?.stop()
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            positionTask?.cancel()
        } else {
            player.play()
            positionTask = Task { @MainActor in
                while !Task.isCancelled {
                    currentTime = player.currentTime
                    if player.currentTime >= player.duration {
                        isPlaying = false
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        isPlaying.toggle()
    }

    private func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    private func seekRelative(_ delta: TimeInterval) {
        guard let player else { return }
        seek(to: max(0, min(player.duration, player.currentTime + delta)))
    }

    // MARK: - Phase Marking

    private func markPhaseStart(_ phase: HypnosisMetadata.Phase) {
        if !file.phases.isEmpty {
            file.phases[file.phases.count - 1].endTime = currentTime
        }
        file.phases.append(LabeledFile.LabeledPhase(
            phase: phase,
            startTime: currentTime,
            endTime: file.audioDuration
        ))
    }

    private func saveFile() {
        file.labeledAt = Date()
        try? corpus.save(file)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m):\(s < 10 ? "0" : "")\(s)"
    }

    private func phaseColor(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .preTalk:      return .indigo
        case .induction:    return .blue
        case .deepening:    return .teal
        case .therapy:      return .purple
        case .suggestions:  return .pink
        case .conditioning: return .orange
        case .emergence:    return .green
        case .transitional: return .gray
        }
    }
}
