//
//  MindMachineView.swift
//  Ilumionate
//
//  Mind Machine Interface for manual light therapy control
//

import SwiftUI

@MainActor
@Observable
final class MindMachineModel: Sendable {
    var frequency: Double = 10.0        // Hz
    var intensity: Double = 0.75        // 0.0 to 1.0
    var colorTemperature: Int = 3000     // Kelvin
    var selectedPattern: LightPattern = .sine
    var isSessionActive: Bool = false

    // Color temperature options
    let temperatureOptions = [2700, 3000, 4000, 5000, 6500]

    enum VisualMode: String, CaseIterable {
        case fullScreenFlash = "Flash"
        case colorPulse      = "Color"
        case bilateralFlash  = "Bilateral"

        var icon: String {
            switch self {
            case .fullScreenFlash: return "flashlight.on.fill"
            case .colorPulse:      return "paintpalette.fill"
            case .bilateralFlash:  return "circle.lefthalf.filled"
            }
        }
    }

    var selectedVisualMode: VisualMode = .fullScreenFlash

    // MARK: - Session Browser
    var sessionCategory: SessionCategory = .all

    // MARK: - Binaural Beats Settings
    var binauralEnabled: Bool = false
    var binauralCarrierFrequency: Double = 200.0   // Hz — left ear carrier
    var binauralVolume: Double = 0.5

    enum LightPattern: String, CaseIterable {
        case sine = "Sine"
        case square = "Square"
        case triangle = "Triangle"
        case sawtooth = "Sawtooth"
        case pulse = "Pulse"

        var description: String {
            switch self {
            case .sine: return "Smooth waves"
            case .square: return "Sharp pulses"
            case .triangle: return "Rising waves"
            case .sawtooth: return "Ramped pulses"
            case .pulse: return "Brief flashes"
            }
        }

        var gradient: LinearGradient {
            switch self {
            case .sine:
                return LinearGradient(colors: [.bwAlpha, .roseGold], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .square:
                return LinearGradient(colors: [.bwBeta, .warmAccent], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .triangle:
                return LinearGradient(colors: [.bwTheta, .lavender], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .sawtooth:
                return LinearGradient(colors: [.bwGamma, .blush], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .pulse:
                return LinearGradient(colors: [.roseDeep, .roseGold], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    // MARK: - Derived Presentation Helpers
    // Pure functions of model state, shared by the view's child components.

    var brainwaveZone: String {
        switch frequency {
        case 0.5..<4: return "Delta"
        case 4..<8: return "Theta"
        case 8..<12: return "Alpha"
        case 12..<30: return "Beta"
        default: return "Gamma"
        }
    }

    var brainwaveColor: Color {
        switch frequency {
        case 0.5..<4: return .bwDelta
        case 4..<8: return .bwTheta
        case 8..<12: return .bwAlpha
        case 12..<30: return .bwBeta
        default: return .bwGamma
        }
    }

    /// Maps the live frequency to a brainwave category for AuroraBackground mood.
    /// Bands match BrainwaveCategory's own frequencyRange/haloColor so the aurora
    /// tint agrees with the model's brainwaveColor.
    var moodCategory: BrainwaveCategory {
        switch frequency {
        case 0.5..<4:   return .sleep   // delta  → bwDelta
        case 4..<8:     return .relax   // theta  → bwTheta
        case 8..<14:    return .focus   // alpha  → bwAlpha
        case 14..<30:   return .energy  // beta   → bwBeta
        default:        return .trance  // gamma  → bwGamma
        }
    }

    func colorForTemperature(_ temp: Int) -> Color {
        switch temp {
        case 2700: return .warmAccent
        case 3000: return .roseGold
        case 4000: return .blush
        case 5000: return .lavender
        case 6500: return .bwBeta
        default: return .roseGold
        }
    }

    var startSessionButtonTitle: String {
        switch selectedVisualMode {
        case .colorPulse:
            return "Start Color Pulse"
        case .bilateralFlash:
            return binauralEnabled ? "Start Bilateral + Binaural" : "Start Bilateral Flash"
        case .fullScreenFlash:
            return binauralEnabled ? "Start Flash + Binaural" : "Start Flash Session"
        }
    }

    var startSessionIcon: String {
        switch selectedVisualMode {
        case .colorPulse:
            return "paintpalette.fill"
        default:
            return binauralEnabled ? "headphones" : "play.fill"
        }
    }
}

struct MindMachineView: View {
    let engine: LightEngine
    let sessions: [LightSession]

    @State var model = MindMachineModel()
    @State private var showingFlashMode = false
    @State var selectedSession: LightSession?
    @State private var showAdvanced = false

    var body: some View {
        ZStack {
            AuroraBackground(mood: model.moodCategory)
            ScrollView {
                VStack(spacing: TranceSpacing.cardMargin) {
                    // Light Visualization + frequency — always visible
                    LightVisualizationCard(model: model)
                    FrequencyCard(model: model)

                    // Advanced controls — hidden by default
                    AdvancedControlsSection(model: model, showAdvanced: $showAdvanced)

                    // Browse research sessions
                    if !sessions.isEmpty {
                        BrowseSessionsLink(sessionCount: sessions.count)
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.statusBar)
                .padding(.bottom, TranceSpacing.tabBarClearance)
            }
            .safeAreaInset(edge: .bottom) {
                MindMachineStartBar(model: model, onStart: startMindMachine)
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { destination in
                if destination == "browseSessions" {
                    BrowseSessionsView(
                        sessions: sessions,
                        engine: engine
                    )
                }
            }
            .fullScreenCover(item: $selectedSession) { session in
                UnifiedPlayerView(
                    mode: .session(session: session, audioFile: nil),
                    engine: engine
                )
            }
            .fullScreenCover(isPresented: $showingFlashMode) {
                switch model.selectedVisualMode {
                case .colorPulse:
                    UnifiedPlayerView(
                        mode: .colorPulse(
                            frequency: model.frequency,
                            intensity: model.intensity
                        ),
                        engine: engine
                    )
                default:
                    UnifiedPlayerView(
                        mode: .flashMode(
                            frequency: model.frequency,
                            intensity: model.intensity,
                            colorTemperature: model.colorTemperature,
                            pattern: model.selectedPattern,
                            binauralEnabled: model.binauralEnabled,
                            binauralCarrier: model.binauralCarrierFrequency,
                            binauralVolume: model.binauralVolume
                        ),
                        engine: engine
                    )
                }
            }
            .onChange(of: showingFlashMode) { _, isShowing in
                if isShowing {
                    UsageAnalytics.shared.mindMachineStarted(
                        mode: analyticsMode(model.selectedVisualMode),
                        entryPoint: .create
                    )
                }
            }
        }
    }

    private func analyticsMode(_ mode: MindMachineModel.VisualMode) -> MindMachineMode {
        switch mode {
        case .fullScreenFlash: .flash
        case .colorPulse:      .colorPulse
        case .bilateralFlash:  .bilateral
        }
    }

    private func startMindMachine() {
        TranceHaptics.shared.heavy()
        UsageAnalytics.shared.mindMachineStartRequested(
            mode: analyticsMode(model.selectedVisualMode),
            entryPoint: .create
        )
        showingFlashMode = true
    }
}

// MARK: - Mind Machine Cards (extracted from computed properties)

private struct LightVisualizationCard: View {
    @Bindable var model: MindMachineModel

    var body: some View {
        LiminalCard(label: "Light Visualization") {
            VStack(spacing: TranceSpacing.list) {
                PhoneScreenOrb(
                    frequency: model.frequency,
                    intensity: model.intensity,
                    kelvin: model.colorTemperature,
                    brainwaveColor: model.brainwaveColor
                )
                .frame(width: 120, height: 200)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(model.frequency.formatted(.number.precision(.fractionLength(1)))) Hz")
                            .font(TranceTypography.dataReadout)
                            .foregroundStyle(.textPrimary)
                        Text(model.brainwaveZone)
                            .font(TranceTypography.caption)
                            .foregroundStyle(model.brainwaveColor)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(Int(model.intensity * 100))%")
                            .font(TranceTypography.dataReadout)
                            .foregroundStyle(.textPrimary)
                        Text("Intensity")
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
        }
    }
}

private struct FrequencyCard: View {
    @Bindable var model: MindMachineModel

    var body: some View {
        LiminalCard(label: "Frequency") {
            VStack(spacing: TranceSpacing.list) {
                Text("\(model.frequency.formatted(.number.precision(.fractionLength(1)))) Hz")
                    .font(TranceTypography.dataReadout)
                    .foregroundStyle(.textPrimary)

                Text(model.brainwaveZone)
                    .font(TranceTypography.caption)
                    .foregroundStyle(model.brainwaveColor)
                    .padding(.horizontal, TranceSpacing.inner)
                    .padding(.vertical, TranceSpacing.micro)
                    .background(model.brainwaveColor.opacity(0.1))
                    .clipShape(Capsule())

                CustomSlider(
                    value: $model.frequency,
                    range: 0.5...40.0,
                    trackColor: .glassBorder,
                    thumbColor: model.brainwaveColor,
                    activeColor: model.brainwaveColor
                )
                .onChange(of: model.frequency) { _, _ in
                    TranceHaptics.shared.selection()
                }
            }
        }
    }
}

private struct ColorTemperatureCard: View {
    @Bindable var model: MindMachineModel

    var body: some View {
        LiminalCard(label: "Color Temperature") {
            VStack(spacing: TranceSpacing.list) {
                Text("\(model.colorTemperature)K")
                    .font(TranceTypography.dataReadout)
                    .foregroundStyle(.textPrimary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: TranceSpacing.inner) {
                    ForEach(model.temperatureOptions, id: \.self) { temp in
                        Button {
                            model.colorTemperature = temp
                            TranceHaptics.shared.selection()
                        } label: {
                            Circle()
                                .fill(model.colorForTemperature(temp))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            model.colorTemperature == temp ? Color.textPrimary : Color.clear,
                                            lineWidth: 2
                                        )
                                }
                                .scaleEffect(model.colorTemperature == temp ? 1.2 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.colorTemperature)
                    }
                }
            }
        }
    }
}

private struct IntensityCard: View {
    @Bindable var model: MindMachineModel

    var body: some View {
        LiminalCard(label: "Intensity") {
            IntensityDial(intensity: $model.intensity)
        }
    }
}

private struct PatternSelectionSection: View {
    @Bindable var model: MindMachineModel

    var body: some View {
        LiminalCard(label: "Waveform Pattern") {
            VStack(spacing: TranceSpacing.list) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TranceSpacing.list) {
                        ForEach(MindMachineModel.LightPattern.allCases, id: \.rawValue) { pattern in
                            PatternCard(
                                pattern: pattern,
                                isSelected: model.selectedPattern == pattern
                            ) {
                                model.selectedPattern = pattern
                                TranceHaptics.shared.selection()
                            }
                        }
                    }
                    .padding(.horizontal, TranceSpacing.content)
                }
            }
        }
    }
}

private struct VisualModeCard: View {
    @Bindable var model: MindMachineModel

    var body: some View {
        LiminalCard(label: "Visual Mode") {
            HStack(spacing: TranceSpacing.list) {
                ForEach(MindMachineModel.VisualMode.allCases, id: \.self) { mode in
                    VisualModeButton(
                        mode: mode,
                        isSelected: model.selectedVisualMode == mode
                    ) {
                        model.selectedVisualMode = mode
                        TranceHaptics.shared.selection()
                    }
                }
            }
        }
    }
}

private struct AdvancedControlsSection: View {
    @Bindable var model: MindMachineModel
    @Binding var showAdvanced: Bool

    var body: some View {
        LiminalCard {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(spacing: TranceSpacing.cardMargin) {
                    Divider().background(Color.glassBorder)

                    HStack(spacing: TranceSpacing.cardMargin) {
                        IntensityCard(model: model)
                        ColorTemperatureCard(model: model)
                    }

                    VisualModeCard(model: model)
                    PatternSelectionSection(model: model)
                    BinauralCard(model: model)
                }
                .padding(.top, TranceSpacing.list)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline)
                        .foregroundStyle(Color.roseGold)
                    Text("Advanced Controls")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .tint(Color.roseGold)
        }
    }
}

private struct BrowseSessionsLink: View {
    let sessionCount: Int

    var body: some View {
        NavigationLink(value: "browseSessions") {
            LiminalCard {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title3)
                        .foregroundStyle(Color.roseGold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browse Sessions")
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                        Text("\(sessionCount) research sessions")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Visual Mode Button Component

struct VisualModeButton: View {
    let mode: MindMachineModel.VisualMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: TranceSpacing.micro) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.roseGold : Color.textSecondary)
                Text(mode.rawValue)
                    .font(TranceTypography.caption)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TranceSpacing.inner)
            .background(isSelected ? Color.roseGold.opacity(0.12) : Color.clear)
            .clipShape(.rect(cornerRadius: TranceRadius.tabItem))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Pattern Card Component

struct PatternCard: View {
    let pattern: MindMachineModel.LightPattern
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: TranceSpacing.inner) {
                ZStack {
                    RoundedRectangle(cornerRadius: TranceRadius.pattern)
                        .fill(Color.bgSecondary.opacity(0.6))
                        .frame(width: 80, height: 50)
                    WaveformShape(pattern: pattern)
                        .stroke(
                            LinearGradient(colors: [.roseGold, .roseDeep], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 64, height: 30)
                        .shadow(color: .roseGold.opacity(isSelected ? 0.7 : 0.4), radius: isSelected ? 10 : 6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: TranceRadius.pattern)
                        .stroke(isSelected ? Color.roseGold : Color.clear, lineWidth: 2)
                        .frame(width: 80, height: 50)
                }

                VStack(spacing: 2) {
                    Text(pattern.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.textPrimary)

                    Text(pattern.description)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom Slider Component

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

// MARK: - Phone Screen Orb

/// A subtle phone-silhouette visualizer that breathes at the session frequency.
struct PhoneScreenOrb: View {
    let frequency: Double
    let intensity: Double
    let kelvin: Int
    let brainwaveColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // Slow sine breath — one in-out per cycle defined by frequency
            let cycleLen = max(0.5, 1.0 / frequency)
            let phase = (t.truncatingRemainder(dividingBy: cycleLen)) / cycleLen  // 0..1
            let breath = 0.5 + 0.5 * sin(phase * .pi * 2)         // 0..1 smooth

            ZStack {
                // Ambient glow behind the phone — very soft
                RoundedRectangle(cornerRadius: 28)
                    .fill(brainwaveColor.opacity(0.12 + 0.10 * breath))
                    .blur(radius: 18)
                    .scaleEffect(1.08 + 0.06 * breath)

                // Phone body
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.bgSecondary,
                                brainwaveColor.opacity(0.06 + 0.10 * breath)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.glassBorder, lineWidth: 1.5)
                    )

                // Screen glow fill — reads kelvin + intensity
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.fromKelvin(kelvin).opacity(
                                    (0.15 + 0.45 * breath) * intensity
                                ),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 55
                        )
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 20)

                // Top notch pill
                VStack {
                    Capsule()
                        .fill(Color.glassBorder.opacity(0.8))
                        .frame(width: 30, height: 5)
                        .padding(.top, 10)
                    Spacer()
                }

                // Bottom home-bar line
                VStack {
                    Spacer()
                    Capsule()
                        .fill(Color.glassBorder.opacity(0.6))
                        .frame(width: 36, height: 4)
                        .padding(.bottom, 10)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MindMachineView(engine: LightEngine(), sessions: [])
    }
}
