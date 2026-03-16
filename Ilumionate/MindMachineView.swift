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
}

struct MindMachineView: View {
    @State private var model = MindMachineModel()
    @State private var showingFlashMode = false
    @State private var showingSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.cardMargin) {
                // Light Visualization
                lightVisualizationSection

                // Controls grid
                HStack(spacing: TranceSpacing.cardMargin) {
                    VStack(spacing: TranceSpacing.cardMargin) {
                        frequencyCard
                        colorTemperatureCard
                    }

                    VStack(spacing: TranceSpacing.cardMargin) {
                        intensityCard
                        startSessionCard
                    }
                }

                // Visual mode selector
                visualModeCard

                // Pattern selection
                patternSelectionSection
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.top, TranceSpacing.statusBar)
            .padding(.bottom, TranceSpacing.tabBarClearance)
        }
        .background(Color.bgPrimary)
        .navigationTitle("Mind Machine")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") {
                    TranceHaptics.shared.light()
                    showingSettings = true
                }
                .foregroundStyle(Color.roseGold)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showingFlashMode) {
            switch model.selectedVisualMode {
            case .colorPulse:
                ColorPulseView(frequency: model.frequency, intensity: model.intensity)
            default:
                FlashModeView(
                    frequency: model.frequency,
                    intensity: model.intensity,
                    colorTemperature: model.colorTemperature,
                    pattern: model.selectedPattern
                )
            }
        }
    }

    // MARK: - Light Visualization Section

    private var lightVisualizationSection: some View {
        GlassCard(label: "Light Visualization") {
            VStack(spacing: TranceSpacing.list) {
                PhoneScreenOrb(
                    frequency: model.frequency,
                    intensity: model.intensity,
                    kelvin: model.colorTemperature,
                    brainwaveColor: brainwaveColor
                )
                .frame(width: 120, height: 200)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(model.frequency, specifier: "%.1f") Hz")
                            .font(TranceTypography.frequency)
                            .foregroundColor(.textPrimary)
                        Text(brainwaveZone)
                            .font(TranceTypography.caption)
                            .foregroundColor(brainwaveColor)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(Int(model.intensity * 100))%")
                            .font(TranceTypography.frequency)
                            .foregroundColor(.textPrimary)
                        Text("Intensity")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Frequency Card

    private var frequencyCard: some View {
        GlassCard(label: "Frequency") {
            VStack(spacing: TranceSpacing.list) {
                Text("\(model.frequency, specifier: "%.1f") Hz")
                    .font(TranceTypography.frequency)
                    .foregroundColor(.textPrimary)

                Text(brainwaveZone)
                    .font(TranceTypography.caption)
                    .foregroundColor(brainwaveColor)
                    .padding(.horizontal, TranceSpacing.inner)
                    .padding(.vertical, TranceSpacing.micro)
                    .background(brainwaveColor.opacity(0.1))
                    .clipShape(Capsule())

                CustomSlider(
                    value: $model.frequency,
                    range: 0.5...40.0,
                    trackColor: .glassBorder,
                    thumbColor: brainwaveColor,
                    activeColor: brainwaveColor
                )
                .onChange(of: model.frequency) { _, _ in
                    TranceHaptics.shared.selection()
                }
            }
        }
    }

    // MARK: - Color Temperature Card

    private var colorTemperatureCard: some View {
        GlassCard(label: "Color Temperature") {
            VStack(spacing: TranceSpacing.list) {
                Text("\(model.colorTemperature)K")
                    .font(TranceTypography.frequency)
                    .foregroundColor(.textPrimary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: TranceSpacing.inner) {
                    ForEach(model.temperatureOptions, id: \.self) { temp in
                        Circle()
                            .fill(colorForTemperature(temp))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(
                                        model.colorTemperature == temp ? Color.textPrimary : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                            .scaleEffect(model.colorTemperature == temp ? 1.2 : 1.0)
                            .onTapGesture {
                                model.colorTemperature = temp
                                TranceHaptics.shared.selection()
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.colorTemperature)
                    }
                }
            }
        }
    }

    // MARK: - Intensity Card

    private var intensityCard: some View {
        GlassCard(label: "Intensity") {
            IntensityDial(intensity: $model.intensity)
        }
    }

    // MARK: - Start Session Card

    private var startSessionCard: some View {
        GlassCard {
            VStack(spacing: TranceSpacing.list) {
                Button(action: {
                    showingFlashMode = true
                    TranceHaptics.shared.heavy()
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Session")
                            .font(TranceTypography.body)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, TranceSpacing.list)
                    .padding(.horizontal, TranceSpacing.card)
                    .background(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                    .shadow(
                        color: TranceShadow.button.color,
                        radius: TranceShadow.button.radius,
                        x: TranceShadow.button.x,
                        y: TranceShadow.button.y
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Text("Enter full-screen flash mode")
                    .font(TranceTypography.caption)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Pattern Selection Section

    private var patternSelectionSection: some View {
        GlassCard(label: "Waveform Pattern") {
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

    // MARK: - Visual Mode Card

    private var visualModeCard: some View {
        GlassCard(label: "Visual Mode") {
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

    // MARK: - Helper Properties

    private var brainwaveZone: String {
        switch model.frequency {
        case 0.5..<4:
            return "Delta"
        case 4..<8:
            return "Theta"
        case 8..<12:
            return "Alpha"
        case 12..<30:
            return "Beta"
        default:
            return "Gamma"
        }
    }

    private var brainwaveColor: Color {
        switch model.frequency {
        case 0.5..<4:
            return .bwDelta
        case 4..<8:
            return .bwTheta
        case 8..<12:
            return .bwAlpha
        case 12..<30:
            return .bwBeta
        default:
            return .bwGamma
        }
    }

    private func colorForTemperature(_ temp: Int) -> Color {
        switch temp {
        case 2700:
            return .warmAccent
        case 3000:
            return .roseGold
        case 4000:
            return .blush
        case 5000:
            return .lavender
        case 6500:
            return .bwBeta
        default:
            return .roseGold
        }
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
        VStack(spacing: TranceSpacing.inner) {
            RoundedRectangle(cornerRadius: TranceRadius.pattern)
                .fill(pattern.gradient)
                .frame(width: 80, height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: TranceRadius.pattern)
                        .stroke(
                            isSelected ? Color.textPrimary : Color.clear,
                            lineWidth: 2
                        )
                )

            VStack(spacing: 2) {
                Text(pattern.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Text(pattern.description)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .onTapGesture(perform: action)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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

                // Thumb
                Circle()
                    .fill(thumbColor)
                    .frame(width: 20, height: 20)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
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
        MindMachineView()
    }
}