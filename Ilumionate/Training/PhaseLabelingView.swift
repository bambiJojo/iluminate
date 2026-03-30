//
//  PhaseLabelingView.swift
//  Ilumionate
//
//  Quick-label and refine UI for ground-truth phase annotation.
//

import SwiftUI
import AVFoundation

struct PhaseLabelingView: View {

    @State var file: LabeledFile
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var isRefineMode = false
    @State private var positionTask: Task<Void, Never>?
    @State private var editingPhase: LabeledFile.LabeledPhase?
    @State private var phaseNotes = ""

    @Environment(\.dismiss) private var dismiss

    private let allPhases: [HypnosisMetadata.Phase] = [
        .preTalk, .induction, .deepening, .therapy,
        .suggestions, .conditioning, .emergence
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.content) {
                playerControls
                if isRefineMode {
                    refineTimeline
                    techniqueSection
                } else {
                    quickLabelButtons
                }
                metadataSection
                phaseList
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.bottom, TranceSpacing.tabBarClearance)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Label Phases")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button(isRefineMode ? "Quick Label" : "Refine") {
                        isRefineMode.toggle()
                    }
                    .foregroundStyle(Color.roseGold)

                    Button("Save") { saveFile() }
                        .bold()
                        .foregroundStyle(Color.roseGold)
                }
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { cleanup() }
        .alert("Phase Notes", isPresented: Binding(
            get: { editingPhase != nil },
            set: { if !$0 { editingPhase = nil } }
        )) {
            TextField("Notes", text: $phaseNotes)
            Button("Save") {
                if let editing = editingPhase,
                   let idx = file.phases.firstIndex(where: { $0.id == editing.id }) {
                    file.phases[idx].notes = phaseNotes
                }
                editingPhase = nil
            }
            Button("Cancel", role: .cancel) { editingPhase = nil }
        }
    }

    // MARK: - Player Controls

    private var playerControls: some View {
        GlassCard {
            VStack(spacing: TranceSpacing.list) {
                HStack {
                    Text(formatTime(currentTime))
                        .monospacedDigit()
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(formatTime(file.audioDuration))
                        .monospacedDigit()
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Slider(value: $currentTime, in: 0...max(file.audioDuration, 1)) { editing in
                    if !editing {
                        player?.currentTime = currentTime
                    }
                }
                .tint(.roseGold)

                HStack(spacing: TranceSpacing.card) {
                    Button("Rewind 10s", systemImage: "gobackward.10") {
                        seekRelative(-10)
                    }
                    .foregroundStyle(Color.textSecondary)

                    Button(isPlaying ? "Pause" : "Play",
                           systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill") {
                        togglePlayback()
                    }
                    .font(.system(size: 44))
                    .foregroundStyle(Color.roseGold)

                    Button("Forward 10s", systemImage: "goforward.10") {
                        seekRelative(10)
                    }
                    .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    // MARK: - Quick Label Buttons

    private var quickLabelButtons: some View {
        GlassCard(label: "Tap to Mark Phase Start") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: TranceSpacing.inner) {
                ForEach(allPhases, id: \.self) { phase in
                    Button {
                        markPhaseStart(phase)
                        TranceHaptics.shared.medium()
                    } label: {
                        Text(phase.displayName)
                            .font(TranceTypography.caption)
                            .bold()
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, TranceSpacing.list)
                            .background(phaseColor(phase))
                            .clipShape(.rect(cornerRadius: TranceRadius.button))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Refine Timeline

    private var refineTimeline: some View {
        GlassCard(label: "Drag Boundaries to Refine") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        ForEach(file.phases) { phase in
                            let startFraction = phase.startTime / max(file.audioDuration, 1)
                            let widthFraction = (phase.endTime - phase.startTime) / max(file.audioDuration, 1)

                            Rectangle()
                                .fill(phaseColor(phase.phase).opacity(0.7))
                                .frame(width: geo.size.width * widthFraction)
                                .offset(x: geo.size.width * startFraction)
                                .overlay(alignment: .center) {
                                    Text(phase.phase.displayName)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                        }

                        let playheadX = (currentTime / max(file.audioDuration, 1)) * geo.size.width
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2)
                            .offset(x: playheadX)
                    }
                }
                .frame(height: 40)
                .clipShape(.rect(cornerRadius: TranceRadius.tabItem))

                Text("Tap a phase in the list below to edit its boundaries and notes")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textLight)
            }
        }
    }

    // MARK: - Technique Section

    private var techniqueSection: some View {
        GlassCard(label: "Techniques") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                ForEach(file.techniques) { technique in
                    HStack {
                        Text(technique.name)
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(formatTime(technique.startTime))–\(formatTime(technique.endTime))")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .monospacedDigit()
                    }
                }

                Button("Add Technique", systemImage: "plus") {
                    let technique = LabeledFile.LabeledTechnique(
                        name: "New Technique",
                        startTime: currentTime,
                        endTime: min(currentTime + 60, file.audioDuration)
                    )
                    file.techniques.append(technique)
                }
                .foregroundStyle(Color.roseGold)
            }
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        GlassCard(label: "Metadata") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Picker("Content Type", selection: $file.expectedContentType) {
                    ForEach(AnalysisResult.ContentType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }

                HStack {
                    Text("Frequency Band")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Menu {
                        Button("Theta (0.5–10 Hz)") {
                            file.expectedFrequencyBand = .init(lower: 0.5, upper: 10.0)
                        }
                        Button("Alpha (8–12 Hz)") {
                            file.expectedFrequencyBand = .init(lower: 8.0, upper: 12.0)
                        }
                        Button("Low Alpha (6–8 Hz)") {
                            file.expectedFrequencyBand = .init(lower: 6.0, upper: 8.0)
                        }
                        Button("Upper Alpha (9–11 Hz)") {
                            file.expectedFrequencyBand = .init(lower: 9.0, upper: 11.0)
                        }
                    } label: {
                        Text("\(file.expectedFrequencyBand.lower, format: .number.precision(.fractionLength(1)))–\(file.expectedFrequencyBand.upper, format: .number.precision(.fractionLength(1))) Hz")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.roseGold)
                    }
                }

                TextField("Labeler notes...", text: $file.labelerNotes, axis: .vertical)
                    .font(TranceTypography.body)
                    .lineLimit(3...6)
            }
        }
    }

    // MARK: - Phase List

    private var phaseList: some View {
        GlassCard(label: "Phases (\(file.phases.count))") {
            if file.phases.isEmpty {
                Text("No phases marked yet. Play the audio and tap phase buttons above.")
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textLight)
            } else {
                ForEach(file.phases) { phase in
                    HStack(spacing: TranceSpacing.inner) {
                        Circle()
                            .fill(phaseColor(phase.phase))
                            .frame(width: 10, height: 10)

                        Text(phase.phase.displayName)
                            .font(TranceTypography.body)
                            .bold()
                            .foregroundStyle(Color.textPrimary)

                        Spacer()

                        Text("\(formatTime(phase.startTime))–\(formatTime(phase.endTime))")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .monospacedDigit()

                        Button("Edit", systemImage: "pencil") {
                            editingPhase = phase
                            phaseNotes = phase.notes ?? ""
                        }
                        .foregroundStyle(Color.roseGold)
                        .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func setupPlayer() {
        let url = TrainingCorpusManager.shared.audioURL(for: file)
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
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        isPlaying.toggle()
    }

    private func seekRelative(_ seconds: TimeInterval) {
        guard let player else { return }
        let newTime = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = newTime
        currentTime = newTime
    }

    private func markPhaseStart(_ phase: HypnosisMetadata.Phase) {
        if !file.phases.isEmpty {
            let idx = file.phases.count - 1
            file.phases[idx].endTime = currentTime
        }

        let newPhase = LabeledFile.LabeledPhase(
            phase: phase,
            startTime: currentTime,
            endTime: file.audioDuration
        )
        file.phases.append(newPhase)
    }

    private func saveFile() {
        file.labeledAt = Date()
        try? TrainingCorpusManager.shared.save(file)
        TranceHaptics.shared.medium()
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m):\(s < 10 ? "0" : "")\(s)"
    }

    private func phaseColor(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .preTalk:      return .bwAlpha
        case .induction:    return .phaseInduction
        case .deepening:    return .phaseDeepener
        case .therapy:      return .phaseSuggestion
        case .suggestions:  return .bwTheta
        case .conditioning: return .bwGamma
        case .emergence:    return .bwBeta
        case .transitional: return .textLight
        }
    }
}
