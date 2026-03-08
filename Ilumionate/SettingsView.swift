//
//  SettingsView.swift
//  Ilumionate
//
//  Redesigned SettingsView for Trance UI
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Core Settings
    @State private var hapticFeedbackEnabled = true
    @State private var autoLockEnabled = true
    @State private var sessionNotifications = true
    @State private var breathingGuidanceEnabled = true
    
    // Session Defaults
    @State private var defaultIntensity = 0.7
    @State private var preferredSessionDuration = 15.0
    @State private var bilateralModeDefault = false
    
    // Audio & Display
    @State private var audioQualityMode = AudioQuality.high
    @State private var displayBrightness = 0.8
    @State private var keepScreenOn = true
    
    // Privacy
    @State private var analyticsEnabled = false
    @State private var showDeveloperOptions = false
    
    enum AudioQuality: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case lossless = "Lossless"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: TranceSpacing.cardMargin) {
                        coreSettingsSection
                        sessionDefaultsSection
                        audioDisplaySection
                        privacyDataSection
                        supportAboutSection
                        
                        if showDeveloperOptions {
                            developerOptionsSection
                        }
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.vertical, TranceSpacing.cardMargin)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Core Settings Section
    private var coreSettingsSection: some View {
        GlassCard(label: "Core Settings") {
            VStack(spacing: TranceSpacing.list) {
                settingsToggle(
                    title: "Haptic Feedback",
                    binding: $hapticFeedbackEnabled,
                    icon: "iphone.radiowaves.left.and.right",
                    color: .roseGold
                )
                
                settingsToggle(
                    title: "Session Lock",
                    binding: $autoLockEnabled,
                    icon: "lock.circle",
                    color: .bwTheta
                )
                
                settingsToggle(
                    title: "Notifications",
                    binding: $sessionNotifications,
                    icon: "bell.circle",
                    color: .bwAlpha
                )
                
                settingsToggle(
                    title: "Breathing Guidance",
                    binding: $breathingGuidanceEnabled,
                    icon: "wind.circle",
                    color: .bwDelta
                )
            }
        }
    }
    
    // MARK: - Session Defaults
    private var sessionDefaultsSection: some View {
        GlassCard(label: "Session Defaults") {
            VStack(spacing: TranceSpacing.list) {
                settingsSlider(
                    title: "Default Intensity",
                    value: $defaultIntensity,
                    range: 0.1...1.0,
                    format: { "\($0 * 100)%" },
                    color: .bwBeta
                )
                
                settingsSlider(
                    title: "Preferred Duration",
                    value: $preferredSessionDuration,
                    range: 5...60,
                    format: { "\($0) min" },
                    color: .bwDelta
                )
                
                settingsToggle(
                    title: "Bilateral Mode Default",
                    binding: $bilateralModeDefault,
                    icon: "brain.head.profile",
                    color: .bwGamma
                )
            }
        }
    }
    
    // MARK: - Audio & Display Section
    private var audioDisplaySection: some View {
        GlassCard(label: "Audio & Display") {
            VStack(spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 16))
                        .foregroundColor(.bwGamma)
                        .frame(width: 24)
                    
                    Text("Audio Quality")
                        .font(TranceTypography.body)
                        .foregroundColor(.textPrimary)
                    
                    Spacer()
                    
                    Picker("Audio Quality", selection: $audioQualityMode) {
                        ForEach(AudioQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    .tint(.textSecondary)
                }
                
                settingsSlider(
                    title: "Display Brightness",
                    value: $displayBrightness,
                    range: 0.1...1.0,
                    format: { "\($0 * 100)%" },
                    color: .bwTheta
                )
                
                settingsToggle(
                    title: "Keep Screen On",
                    binding: $keepScreenOn,
                    icon: "sun.max.circle",
                    color: .bwAlpha
                )
            }
        }
    }
    
    // MARK: - Privacy & Data Section
    private var privacyDataSection: some View {
        GlassCard(label: "Privacy & Data") {
            VStack(spacing: TranceSpacing.list) {
                settingsToggle(
                    title: "Anonymous Analytics",
                    binding: $analyticsEnabled,
                    icon: "chart.bar",
                    color: .textSecondary
                )
                
                settingsButton(title: "Export Session Data", icon: "square.and.arrow.up.circle") {
                    TranceHaptics.shared.light()
                }
                
                settingsButton(title: "Clear All Data", icon: "trash.circle", color: .roseDeep) {
                    TranceHaptics.shared.heavy()
                }
            }
        }
    }
    
    // MARK: - Support & About Section
    private var supportAboutSection: some View {
        GlassCard(label: "Support") {
            VStack(spacing: TranceSpacing.list) {
                settingsButton(title: "Help & Support", icon: "questionmark.circle") {
                    TranceHaptics.shared.light()
                }
                
                settingsButton(title: "About Ilumionate", icon: "heart.circle") {
                    TranceHaptics.shared.light()
                }
                
                Button("") {
                    showDeveloperOptions.toggle()
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onTapGesture(count: 5) {
                    showDeveloperOptions.toggle()
                    TranceHaptics.shared.heavy()
                }
            }
        }
    }
    
    // MARK: - Developer Options Section
    private var developerOptionsSection: some View {
        GlassCard(label: "Developer Settings") {
            VStack(spacing: TranceSpacing.list) {
                settingsButton(title: "Engine Diagnostics", icon: "cpu", color: .roseDeep) {
                    TranceHaptics.shared.light()
                }
                
                settingsButton(title: "Reset Preferences", icon: "arrow.clockwise.circle", color: .roseDeep) {
                    TranceHaptics.shared.heavy()
                }
            }
        }
    }
    
    // MARK: - Helper Modifiers
    private func settingsToggle(
        title: String,
        binding: Binding<Bool>,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(TranceTypography.body)
                .foregroundColor(.textPrimary)
            
            Spacer()
            
            Toggle("", isOn: binding)
                .toggleStyle(RoseToggleStyle())
                .labelsHidden()
        }
    }
    
    private func settingsSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: (Double) -> String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: TranceSpacing.micro) {
            HStack {
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Text(format(value.wrappedValue))
                    .font(TranceTypography.caption)
                    .foregroundColor(.textSecondary)
            }
            
            CustomSlider(
                value: value,
                range: range,
                trackColor: .glassBorder,
                thumbColor: color,
                activeColor: color
            )
        }
    }
    
    private func settingsButton(
        title: String,
        icon: String,
        color: Color = .textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 24)
                
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundColor(color == .textSecondary ? .textPrimary : color)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.textLight)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SettingsView()
}