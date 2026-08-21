//
//  ProfileSettingsView.swift
//  Ilumionate
//
//  Unified Profile + Settings view. Combines user profile, listening stats,
//  weekly activity, all app settings, and AI analysis preferences into a
//  single sheet accessible from the Home avatar button.
//

import SwiftUI
import StoreKit

// MARK: - ProfileSettingsView

struct ProfileSettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) var openURL
    @Environment(\.requestReview) var requestReview

    // Profile
    @AppStorage("profileName") var profileName = ""
    @AppStorage("profileGoal") var profileGoal = ""
    @State var isEditingProfile = false
    @State var draftName = ""
    @State var draftGoal = ""

    // Core Settings
    @AppStorage("hapticFeedbackEnabled") var hapticFeedbackEnabled = true
    @AppStorage("autoLockEnabled") var autoLockEnabled = true
    @AppStorage("appearanceMode") var appearanceModeRaw = ThemeMode.system.rawValue

    // Session Defaults
    @AppStorage("userFrequencyMultiplier") var userFrequencyMultiplier = 1.0
    @AppStorage("countdownDuration") var countdownDuration = 3
    @AppStorage("maximumLightTimeMinutes") var maximumLightTimeMinutes =
        LightExposureLimit.recommended.rawValue
    @AppStorage("steadyLightEnabled") var steadyLightEnabled = false
    @State var flashTint: FlashTint = .default
    @State var showingFlashTintSheet = false
    @AppStorage("focusSpotsEnabled") var focusSpotsEnabled = false
    @State var showingFocusSpotCalibration = false
    /// True when calibration was opened by switching the toggle on, so
    /// cancelling has to switch it back off — backing out of the automatic
    /// screen must not leave the feature on with untuned defaults.
    @State var focusSpotCalibrationOpenedByToggle = false

    // Privacy
    @AppStorage("listeningHistoryEnabled") var listeningHistoryEnabled = true
    @AppStorage("analyticsConsentGranted") var analyticsEnabled = false

    // Content — reveals adult (18+) reading sources when enabled. Off by default.
    @AppStorage("nsfwSourcesEnabled") var nsfwSourcesEnabled = false
    @State var pendingNSFWEnable = false

    // Analysis Preferences
    @State var prefs = AnalysisPreferences.shared

    // Alerts
    @State var showClearDataAlert = false
    @State var showClearDataDone = false
    @State var showDeveloperOptions = false
    @State var showAbout = false
    #if DEBUG
    @State var showAnalyzerTraining = false
    #endif

    @State var animateContent = false

    let history = SessionHistoryManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: TranceSpacing.cardMargin) {
                        avatarHeader
                        statsRow
                        weeklyActivityCard
                        coreSettingsSection
                        sessionDefaultsSection
                        lightSyncPreferencesSection
                        privacyDataSection
                        recentSessionsCard
                        supportAboutSection

                        if showDeveloperOptions {
                            developerOptionsSection
                        }

                        Text(
                            "LumeSync v\(Bundle.main.appVersion) (\(Bundle.main.buildNumber))"
                        )
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textLight)
                        .padding(.bottom, TranceSpacing.card)
                    }
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.vertical, TranceSpacing.cardMargin)
                }
            }
            .navigationTitle("Profile & Settings")
            .platformLargeNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.roseGold)
                }
            }
            .sheet(isPresented: $isEditingProfile) { profileEditor }
            .sheet(isPresented: $showAbout) { aboutSheet }
            .sheet(isPresented: $showingFlashTintSheet) {
                FlashTintSheet(selection: $flashTint)
            }
            .platformFullScreenCover(isPresented: $showingFocusSpotCalibration) {
                FocusSpotCalibrationView(
                    initialSettings: FocusSpotPreference.current(),
                    onSave: { settings in
                        FocusSpotPreference.set(settings)
                        showingFocusSpotCalibration = false
                    },
                    onCancel: {
                        if focusSpotCalibrationOpenedByToggle {
                            focusSpotsEnabled = false
                        }
                        showingFocusSpotCalibration = false
                    }
                )
            }
            .onChange(of: focusSpotsEnabled) { _, enabled in
                // Cancelling sets this false, which re-enters here; the guard
                // stops that from re-presenting the screen.
                guard enabled else { return }
                focusSpotCalibrationOpenedByToggle = true
                showingFocusSpotCalibration = true
            }
            .task { flashTint = FlashTintPreference.current() }
            .onChange(of: flashTint) { _, newValue in
                FlashTintPreference.set(newValue)
            }
            .alert("Clear All Data?", isPresented: $showClearDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { clearAllData() }
            } message: {
                Text("This will permanently delete all audio files, playlists, and sessions. This cannot be undone.")
            }
            .alert("Cleared", isPresented: $showClearDataDone) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("All app data has been removed from this device.")
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.15)) {
                    animateContent = true
                }
            }
        }
    }

}

// MARK: - Preview

#Preview {
    ProfileSettingsView()
}
