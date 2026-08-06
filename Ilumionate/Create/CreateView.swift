//  CreateView.swift
//  Ilumionate
//
//  The Create tab: pick what you are making, see it, tune it, start it.
//
//  Mode first and nothing buried. The previous screen hid the kind picker,
//  intensity, warmth, waveform and binaural inside one collapsed disclosure —
//  burial was the actual problem, so every control here has a tile.

import SwiftUI

struct CreateView: View {
    let engine: LightEngine

    @State private var kind: CreateSessionKind = .visualField
    @State private var light = MindMachineModel()
    @State private var store = VisualFieldStore.shared
    @State private var showingTintSheet = false
    @State private var showingAudioSheet = false
    @State private var showingPlayer = false
    @State private var accompanyingTrack: AudioFile?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visualBinding: Binding<VisualFieldSettings> {
        Binding(get: { store.settings }, set: { store.settings = $0 })
    }

    var body: some View {
        ZStack {
            AuroraBackground(mood: light.moodCategory)

            ScrollView {
                VStack(spacing: TranceSpacing.cardMargin) {
                    kindPicker

                    CreateFieldPreview(
                        kind: kind,
                        visual: store.settings,
                        light: light
                    )
                    .padding(.horizontal, TranceSpacing.screen)

                    if reduceMotion && kind == .visualField {
                        reduceMotionNotice
                    }

                    CreateControlTray(
                        kind: kind,
                        visual: visualBinding,
                        light: light,
                        showingTintSheet: $showingTintSheet
                    )

                    if kind == .visualField {
                        audioRow
                    }
                }
                .padding(.top, TranceSpacing.statusBar)
                .padding(.bottom, TranceSpacing.tabBarClearance)
            }
            .safeAreaInset(edge: .bottom) {
                CreateStartBar(
                    kind: kind,
                    visual: store.settings,
                    light: light,
                    onStart: start
                )
            }
        }
        .navigationTitle("Create")
        .platformLargeNavigationTitle()
        .sheet(isPresented: $showingTintSheet) {
            CreateTintSheet(tint: visualBinding.tint)
        }
        .sheet(isPresented: $showingAudioSheet) {
            CreateAudioSheet(
                track: $accompanyingTrack,
                binaural: Binding(
                    get: { store.binaural },
                    set: { store.binaural = $0 }
                )
            )
        }
        .platformFullScreenCover(isPresented: $showingPlayer) {
            UnifiedPlayerView(
                mode: playerMode,
                engine: engine,
                mindMachineEntryPoint: .create,
                mindMachineMode: kind.mindMachineMode
            )
        }
        .onChange(of: kind) { _, newKind in
            UsageAnalytics.shared.createModeSelected(newKind.analyticsMode)
            TranceHaptics.shared.selection()
        }
    }

    // MARK: - Kind picker

    private var kindPicker: some View {
        Picker("Session kind", selection: $kind) {
            ForEach(CreateSessionKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, TranceSpacing.screen)
    }

    /// What rides along with the field. Only the wordless kind shows this: the
    /// light kinds carry their binaural on a tray tile, and none of them takes
    /// an accompanying track.
    private var audioRow: some View {
        Button {
            showingAudioSheet = true
        } label: {
            HStack(spacing: TranceSpacing.inner) {
                Image(systemName: audioSymbol)
                    .foregroundStyle(Color.roseGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audio")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                    Text(audioSummary)
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(TranceSpacing.inner)
            .liminalGlass(.roundedRect(cornerRadius: TranceRadius.glassCard))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, TranceSpacing.screen)
        .accessibilityLabel("Audio")
        .accessibilityValue(audioSummary)
    }

    private var audioSymbol: String {
        if accompanyingTrack != nil { return "music.note" }
        return store.binaural.enabled ? "headphones" : "speaker.slash"
    }

    private var audioSummary: String {
        var parts: [String] = []
        if let accompanyingTrack { parts.append(accompanyingTrack.displayName) }
        if store.binaural.enabled {
            let beat = store.binaural.beatFrequency
                .formatted(.number.precision(.fractionLength(1)))
            parts.append("Binaural \(beat) Hz")
        }
        return parts.isEmpty ? "Silence" : parts.joined(separator: " · ")
    }

    /// Reduce Motion freezes the field. In the reader the visual is decoration,
    /// so a still frame needs no explanation; here it IS the content, and a
    /// Speed tile that does nothing needs one.
    private var reduceMotionNotice: some View {
        Text("Motion is reduced by a system setting, so the field will hold still.")
            .font(TranceTypography.caption)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, TranceSpacing.screen)
    }

    // MARK: - Starting

    private var playerMode: PlayerMode {
        switch kind {
        case .visualField:
            return .visualField(
                settings: store.settings,
                audioFile: accompanyingTrack,
                binaural: store.binaural.enabled ? store.binaural : nil
            )
        case .colourPulse:
            return .colorPulse(frequency: light.frequency, intensity: light.intensity)
        case .flash, .bilateral:
            return .flashMode(
                frequency: light.frequency,
                intensity: light.intensity,
                colorTemperature: light.colorTemperature,
                pattern: light.selectedPattern,
                binauralEnabled: light.binauralEnabled,
                binauralCarrier: light.binauralCarrierFrequency,
                binauralVolume: light.binauralVolume,
                goalDuration: store.settings.duration
            )
        }
    }

    private func start() {
        TranceHaptics.shared.heavy()
        UsageAnalytics.shared.mindMachineStartRequested(
            mode: kind.mindMachineMode,
            entryPoint: .create
        )
        showingPlayer = true
    }
}

#Preview {
    NavigationStack {
        CreateView(engine: LightEngine())
    }
}
