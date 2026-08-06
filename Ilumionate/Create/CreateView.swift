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
    @State private var showingPlayer = false

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
                audioFile: nil,
                binaural: light.binauralEnabled ? light.binauralSettings : nil
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
