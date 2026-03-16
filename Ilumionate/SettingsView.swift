//
//  SettingsView.swift
//  LumeSync
//
//  Core struct, properties, body and helper utilities for Settings.
//  Sections are split into SettingsView+ProfileSection and SettingsView+Sections.
//

import SwiftUI

// MARK: - App Info helpers

extension Bundle {
    var appVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "1" }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // Profile
    @AppStorage("profileName") var profileName = ""
    @AppStorage("profileGoal") var profileGoal = ""
    @State var isEditingProfile = false
    @State var draftName = ""
    @State var draftGoal = ""

    // Appearance
    @AppStorage("appearanceMode") var appearanceModeRaw = "system"

    enum AppearanceMode: String, CaseIterable {
        case system = "system"
        case light  = "light"
        case dark   = "dark"

        var label: String {
            switch self {
            case .system: return "System"
            case .light:  return "Light"
            case .dark:   return "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light:  return .light
            case .dark:   return .dark
            }
        }
    }

    var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    // Core Settings
    @AppStorage("hapticFeedbackEnabled") var hapticFeedbackEnabled = true
    @AppStorage("autoLockEnabled") var autoLockEnabled = true
    @AppStorage("sessionNotifications") var sessionNotifications = true
    @AppStorage("breathingGuidanceEnabled") var breathingGuidanceEnabled = true

    // Session Defaults
    @AppStorage("defaultIntensity") var defaultIntensity = 0.7
    @AppStorage("preferredSessionDuration") var preferredSessionDuration = 15.0
    @AppStorage("bilateralModeDefault") var bilateralModeDefault = false
    @AppStorage("userFrequencyMultiplier") var userFrequencyMultiplier = 1.0

    // Audio & Display
    @AppStorage("audioQualityRaw") var audioQualityRaw = "High"
    @AppStorage("displayBrightness") var displayBrightness = 0.8
    @AppStorage("keepScreenOn") var keepScreenOn = true

    // Privacy
    @AppStorage("analyticsEnabled") var analyticsEnabled = false
    @AppStorage("listeningHistoryEnabled") var listeningHistoryEnabled = false

    @State var showDeveloperOptions = false
    @State var showClearDataAlert = false
    @State var showClearDataDone = false
    @State var showExportDone = false
    @State var showAbout = false

    enum AudioQuality: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case lossless = "Lossless"
    }

    var audioQualityMode: Binding<AudioQuality> {
        Binding(
            get: { AudioQuality(rawValue: audioQualityRaw) ?? .high },
            set: { audioQualityRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: TranceSpacing.cardMargin) {
                        appearanceSection
                        profileSection
                        coreSettingsSection
                        sessionDefaultsSection
                        audioDisplaySection
                        privacyDataSection
                        supportAboutSection

                        if showDeveloperOptions {
                            developerOptionsSection
                        }

                        Text("LumeSync v\(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textLight)
                            .padding(.bottom, TranceSpacing.card)
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.vertical, TranceSpacing.cardMargin)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(appearanceMode.wrappedValue.colorScheme)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $isEditingProfile) { profileEditor }
            .alert("Clear All Data?", isPresented: $showClearDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { clearAllData() }
            } message: {
                Text("This will permanently delete all audio files, playlists, and sessions. This cannot be undone.")
            }
            .alert("Data Exported", isPresented: $showExportDone) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your session data has been exported via the share sheet.")
            }
            .alert("Cleared", isPresented: $showClearDataDone) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("All app data has been removed from this device.")
            }
            .sheet(isPresented: $showAbout) { aboutSheet }
        }
    }

    // MARK: - Profile initials

    private var initials: String {
        let words = profileName.split(separator: " ").prefix(2)
        let joined = words.map { String($0.prefix(1)).uppercased() }.joined()
        return joined.isEmpty ? "?" : joined
    }

    // MARK: - Helper Views

    func settingsToggle(
        title: String,
        binding: Binding<Bool>,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
                .font(TranceTypography.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Toggle("", isOn: binding)
                .toggleStyle(RoseToggleStyle())
                .labelsHidden()
        }
    }

    func settingsSlider(
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
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
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

    func settingsButton(
        title: String,
        icon: String,
        color: Color = .textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(title)
                    .font(TranceTypography.body)
                    .foregroundStyle(color == .textSecondary ? Color.textPrimary : color)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textLight)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    func exportSessionData() {
        let summary = """
        LumeSync Export – \(Date().formatted(.dateTime.day().month().year()))

        Profile
        -------
        Name: \(profileName.isEmpty ? "Not set" : profileName)
        Goal: \(profileGoal.isEmpty ? "Not set" : profileGoal)

        Settings
        --------
        Audio Quality: \(audioQualityRaw)
        Default Intensity: \(String(format: "%.0f%%", defaultIntensity * 100))
        Session Duration: \(String(format: "%.0f min", preferredSessionDuration))
        Bilateral Mode: \(bilateralModeDefault)
        Haptics: \(hapticFeedbackEnabled)
        Keep Screen On: \(keepScreenOn)
        Analytics: \(analyticsEnabled)
        """

        let activityVC = UIActivityViewController(
            activityItems: [summary],
            applicationActivities: nil
        )

        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootVC = windowScene.windows.first?.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }
        topVC.present(activityVC, animated: true)
    }

    func clearAllData() {
        UserDefaults.standard.removeObject(forKey: "audioFiles")
        let docs = URL.documentsDirectory
        if let items = try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: nil
        ) {
            for item in items { try? FileManager.default.removeItem(at: item) }
        }
        TranceHaptics.shared.heavy()
        showClearDataDone = true
    }

    func resetPreferences() {
        hapticFeedbackEnabled = true
        autoLockEnabled = true
        sessionNotifications = true
        breathingGuidanceEnabled = true
        defaultIntensity = 0.7
        preferredSessionDuration = 15.0
        bilateralModeDefault = false
        userFrequencyMultiplier = 1.0
        audioQualityRaw = "High"
        displayBrightness = 0.8
        keepScreenOn = true
        analyticsEnabled = false
        listeningHistoryEnabled = false
    }
}

#Preview {
    SettingsView()
}
