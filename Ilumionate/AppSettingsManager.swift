//
//  AppSettingsManager.swift
//  Ilumionate
//
//  Shared helpers for reading runtime settings and performing export/reset
//  actions from the live settings screen.
//

import Foundation

@MainActor
enum AppSettingsManager {
    nonisolated enum Key {
        static let profileName = "profileName"
        static let profileGoal = "profileGoal"
        static let appearanceMode = "appearanceMode"
        static let hapticFeedbackEnabled = "hapticFeedbackEnabled"
        static let autoLockEnabled = "autoLockEnabled"
        static let userFrequencyMultiplier = "userFrequencyMultiplier"
        static let countdownDuration = "countdownDuration"
        static let maximumLightTimeMinutes = "maximumLightTimeMinutes"
        static let steadyLightEnabled = "steadyLightEnabled"
        static let flashTint = "flashTint"
        static let focusSpotsEnabled = "focusSpotsEnabled"
        static let focusSpots = "focusSpots"
        static let mindMachineEnabled = "mindMachineEnabled"
        static let listeningHistoryEnabled = "listeningHistoryEnabled"
        /// Retired content-directory preference. Kept only so reset can remove
        /// values written by pre-release builds; the App Store build never reads it.
        static let retiredMatureSourcesEnabled = "nsfwSourcesEnabled"
        /// Retired library key. Kept only so reset can clear pre-migration data;
        /// current library reads and writes go through `AudioLibraryStore`.
        static let audioFiles = "audioFiles"
        static let sessionHistory = "sessionHistory_v1"
        static let lastSessionId = "lastSessionId"
        static let lastSessionProgress = "lastSessionProgress"
        static let hasSeenFlashWarning = "hasSeenFlashWarning"
        static let hasSeenLightSyncWarning = "hasSeenLightSyncWarning"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        /// Retired streaming credentials. The SoundCloud integration was removed
        /// in `e9cb0f1`; these are kept only so `purgeRetiredStreamingCredentials`
        /// and reset can delete values written before then. Nothing reads them.
        static let soundCloudClientId = "SoundCloud_ClientId"
        static let soundCloudSecret = "SoundCloud_Secret"
        static let soundCloudAccessToken = "SoundCloud_AccessToken"

        // Legacy or currently-retired settings keys that should not survive resets.
        static let sessionNotifications = "sessionNotifications"
        static let breathingGuidanceEnabled = "breathingGuidanceEnabled"
        static let defaultIntensity = "defaultIntensity"
        static let preferredSessionDuration = "preferredSessionDuration"
        static let bilateralModeDefault = "bilateralModeDefault"
        static let audioQualityRaw = "audioQualityRaw"
        static let displayBrightness = "displayBrightness"
        static let keepScreenOn = "keepScreenOn"
        static let analyticsEnabled = "analyticsEnabled"
        static let analyticsConsentGranted = "analyticsConsentGranted"
        static let analyticsConsentAnswered = "analyticsConsentAnswered"
        static let analyticsActivationStart = "analyticsActivationStart"
        static let analyticsActivationCompleted = "analyticsActivationCompleted"

        static let analysisPrefPrefix = "analysisPref_"
        static let streamingTrackPrefix = "StreamingTrack_"
    }

    struct ExportProfile: Codable, Sendable {
        let name: String
        let goal: String
    }

    struct ExportSettings: Codable, Sendable {
        let appearanceMode: String
        let hapticFeedbackEnabled: Bool
        let keepScreenAwakeDuringSessions: Bool
        let userFrequencyMultiplier: Double
        let countdownDuration: Int
        let maximumLightTimeMinutes: Int
        let listeningHistoryEnabled: Bool
        let mindMachineEnabled: Bool
    }

    struct ExportAudioLibrary: Codable, Sendable {
        let fileCount: Int
        let fileNames: [String]
    }

    struct ExportSnapshot: Codable, Sendable {
        let exportedAt: Date
        let profile: ExportProfile
        let settings: ExportSettings
        let analysisPreferences: AnalysisPreferences.Snapshot
        let sessionHistory: [SessionHistoryEntry]
        let audioLibrary: ExportAudioLibrary
    }

    static func isHapticFeedbackEnabled(defaults: UserDefaults = .standard) -> Bool {
        bool(forKey: Key.hapticFeedbackEnabled, default: true, defaults: defaults)
    }

    static func keepsScreenAwakeDuringSessions(defaults: UserDefaults = .standard) -> Bool {
        bool(forKey: Key.autoLockEnabled, default: true, defaults: defaults)
    }

    static func userFrequencyMultiplier(defaults: UserDefaults = .standard) -> Double {
        let value = defaults.object(forKey: Key.userFrequencyMultiplier) as? Double ?? 1.0
        return max(0.5, min(2.0, value))
    }

    static func countdownDuration(defaults: UserDefaults = .standard) -> Int {
        let value = defaults.object(forKey: Key.countdownDuration) as? Int ?? 3
        return [3, 7, 10].contains(value) ? value : 3
    }

    static func maximumLightTime(defaults: UserDefaults = .standard) -> LightExposureLimit {
        let value = defaults.object(forKey: Key.maximumLightTimeMinutes) as? Int
            ?? LightExposureLimit.recommended.rawValue
        return LightExposureLimit(storedMinutes: value)
    }

    static func isMindMachineEnabled(defaults: UserDefaults = .standard) -> Bool {
        bool(forKey: Key.mindMachineEnabled, default: true, defaults: defaults)
    }

    static func exportSnapshot(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        exportDirectory: URL = FileManager.default.temporaryDirectory,
        audioLibraryStorage: AudioLibraryStorage = .standard,
        analysisPreferencesSnapshot: AnalysisPreferences.Snapshot? = nil
    ) async throws -> URL {
        let audioFiles = await AudioLibraryStore.allFiles(storage: audioLibraryStorage)
        let snapshot = ExportSnapshot(
            exportedAt: Date(),
            profile: ExportProfile(
                name: defaults.string(forKey: Key.profileName) ?? "",
                goal: defaults.string(forKey: Key.profileGoal) ?? ""
            ),
            settings: ExportSettings(
                appearanceMode: defaults.string(forKey: Key.appearanceMode) ?? "system",
                hapticFeedbackEnabled: isHapticFeedbackEnabled(defaults: defaults),
                keepScreenAwakeDuringSessions: keepsScreenAwakeDuringSessions(defaults: defaults),
                userFrequencyMultiplier: userFrequencyMultiplier(defaults: defaults),
                countdownDuration: countdownDuration(defaults: defaults),
                maximumLightTimeMinutes: maximumLightTime(defaults: defaults).rawValue,
                listeningHistoryEnabled: bool(
                    forKey: Key.listeningHistoryEnabled,
                    default: false,
                    defaults: defaults
                ),
                mindMachineEnabled: isMindMachineEnabled(defaults: defaults)
            ),
            analysisPreferences: analysisPreferencesSnapshot ?? AnalysisPreferences.shared.snapshot,
            sessionHistory: sessionHistory(defaults: defaults),
            audioLibrary: audioLibrary(files: audioFiles)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: snapshot.exportedAt).replacingOccurrences(of: ":", with: "-")
        let exportURL = exportDirectory.appending(path: "Ilumionate-Settings-\(timestamp).json")
        let data = try encoder.encode(snapshot)
        try data.write(to: exportURL, options: .atomic)
        return exportURL
    }

    /// Deletes credentials left behind by the retired SoundCloud integration.
    ///
    /// Removing the feature (`e9cb0f1`) removed everything that *read* the client
    /// secret and OAuth token, but not the values themselves: they persist in the
    /// `UserDefaults` plist, which is unencrypted beyond its file-protection class
    /// and is captured in device backups. Anyone who authenticated before the
    /// feature was retired is still carrying them. Runs on every launch — the keys
    /// are never written again, so after the first pass it is a no-op.
    ///
    /// See ERRORS.md ERR-020.
    nonisolated static func purgeRetiredStreamingCredentials(
        defaults: UserDefaults = .standard
    ) {
        for key in [Key.soundCloudClientId, Key.soundCloudSecret, Key.soundCloudAccessToken] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Replaces only the three goal labels written by older onboarding builds.
    /// User-entered profile goals are left untouched.
    nonisolated static func migrateLegacyProfileGoalCopy(
        defaults: UserDefaults = .standard
    ) {
        let replacements = [
            "Deep Relaxation": "Gentle Wind-down",
            "Better Sleep": "Night Session",
            "Focus & Productivity": "Focused Time"
        ]
        guard let stored = defaults.string(forKey: Key.profileGoal),
              let replacement = replacements[stored] else { return }
        defaults.set(replacement, forKey: Key.profileGoal)
    }

    static func resetPreferences(
        defaults: UserDefaults = .standard,
        resetAnalysisPreferences: Bool = true
    ) {
        defaults.set("system", forKey: Key.appearanceMode)
        defaults.set(true, forKey: Key.hapticFeedbackEnabled)
        defaults.set(true, forKey: Key.autoLockEnabled)
        defaults.set(1.0, forKey: Key.userFrequencyMultiplier)
        defaults.set(3, forKey: Key.countdownDuration)
        defaults.set(
            LightExposureLimit.recommended.rawValue,
            forKey: Key.maximumLightTimeMinutes
        )
        defaults.set(false, forKey: Key.steadyLightEnabled)
        defaults.removeObject(forKey: Key.flashTint)
        defaults.set(false, forKey: Key.focusSpotsEnabled)
        defaults.removeObject(forKey: Key.focusSpots)
        defaults.set(true, forKey: Key.mindMachineEnabled)
        defaults.set(false, forKey: Key.listeningHistoryEnabled)
        defaults.removeObject(forKey: Key.retiredMatureSourcesEnabled)

        let retiredKeys = [
            Key.sessionNotifications,
            Key.breathingGuidanceEnabled,
            Key.defaultIntensity,
            Key.preferredSessionDuration,
            Key.bilateralModeDefault,
            Key.audioQualityRaw,
            Key.displayBrightness,
            Key.keepScreenOn,
            Key.analyticsEnabled,
            Key.analyticsConsentGranted,
            Key.analyticsConsentAnswered,
            Key.analyticsActivationStart,
            Key.analyticsActivationCompleted
        ]
        retiredKeys.forEach(defaults.removeObject(forKey:))

        if resetAnalysisPreferences {
            AnalysisPreferences.shared.resetToDefaults()
        }
    }

    static func clearAllData(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        documentsDirectory: URL = URL.documentsDirectory,
        applicationSupportDirectory: URL = AppStoragePaths.supportRoot,
        audioLibraryStorage: AudioLibraryStorage = .standard,
        resetAnalysisPreferences: Bool = true,
        clearSharedHistory: Bool = true
    ) async throws {
        if clearSharedHistory {
            SessionHistoryManager.shared.clearHistory()
        } else {
            defaults.removeObject(forKey: Key.sessionHistory)
        }

        let keysToRemove = [
            Key.profileName,
            Key.profileGoal,
            Key.audioFiles,
            Key.sessionHistory,
            Key.lastSessionId,
            Key.lastSessionProgress,
            Key.hasSeenFlashWarning,
            Key.hasSeenLightSyncWarning,
            Key.hasCompletedOnboarding,
            Key.soundCloudClientId,
            Key.soundCloudSecret,
            Key.soundCloudAccessToken
        ]
        keysToRemove.forEach(defaults.removeObject(forKey:))

        try await AudioLibraryStore.deleteLibrary(storage: audioLibraryStorage)

        removeKeys(withPrefix: Key.streamingTrackPrefix, defaults: defaults)
        resetPreferences(
            defaults: defaults,
            resetAnalysisPreferences: resetAnalysisPreferences
        )

        if fileManager.fileExists(atPath: documentsDirectory.path()) {
            let items = try fileManager.contentsOfDirectory(
                at: documentsDirectory,
                includingPropertiesForKeys: nil
            )
            for item in items {
                try fileManager.removeItem(at: item)
            }
        }

        if fileManager.fileExists(atPath: applicationSupportDirectory.path()) {
            try fileManager.removeItem(at: applicationSupportDirectory)
        }
    }

    private static func sessionHistory(defaults: UserDefaults) -> [SessionHistoryEntry] {
        guard
            let data = defaults.data(forKey: Key.sessionHistory),
            let entries = try? JSONDecoder().decode([SessionHistoryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    private static func audioLibrary(files: [AudioFile]) -> ExportAudioLibrary {
        return ExportAudioLibrary(
            fileCount: files.count,
            fileNames: files.map(\.filename).sorted()
        )
    }

    private static func removeKeys(withPrefix prefix: String, defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func bool(
        forKey key: String,
        default defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
}
