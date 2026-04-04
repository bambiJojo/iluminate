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
    enum Key {
        static let profileName = "profileName"
        static let profileGoal = "profileGoal"
        static let appearanceMode = "appearanceMode"
        static let hapticFeedbackEnabled = "hapticFeedbackEnabled"
        static let autoLockEnabled = "autoLockEnabled"
        static let userFrequencyMultiplier = "userFrequencyMultiplier"
        static let countdownDuration = "countdownDuration"
        static let listeningHistoryEnabled = "listeningHistoryEnabled"
        static let audioFiles = "audioFiles"
        static let sessionHistory = "sessionHistory_v1"
        static let lastSessionId = "lastSessionId"
        static let lastSessionProgress = "lastSessionProgress"
        static let hasSeenFlashWarning = "hasSeenFlashWarning"
        static let hasSeenLightSyncWarning = "hasSeenLightSyncWarning"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
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
        let listeningHistoryEnabled: Bool
    }

    struct ExportAudioLibrary: Codable, Sendable {
        let fileCount: Int
        let fileNames: [String]
    }

    struct ExportStreaming: Codable, Sendable {
        let soundCloudConfigured: Bool
        let soundCloudAuthenticated: Bool
    }

    struct ExportSnapshot: Codable, Sendable {
        let exportedAt: Date
        let profile: ExportProfile
        let settings: ExportSettings
        let analysisPreferences: AnalysisPreferences.Snapshot
        let sessionHistory: [SessionHistoryEntry]
        let audioLibrary: ExportAudioLibrary
        let streaming: ExportStreaming
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

    static func exportSnapshot(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        exportDirectory: URL = FileManager.default.temporaryDirectory,
        analysisPreferencesSnapshot: AnalysisPreferences.Snapshot? = nil
    ) throws -> URL {
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
                listeningHistoryEnabled: bool(
                    forKey: Key.listeningHistoryEnabled,
                    default: false,
                    defaults: defaults
                )
            ),
            analysisPreferences: analysisPreferencesSnapshot ?? AnalysisPreferences.shared.snapshot,
            sessionHistory: sessionHistory(defaults: defaults),
            audioLibrary: audioLibrary(defaults: defaults),
            streaming: ExportStreaming(
                soundCloudConfigured: !(defaults.string(forKey: Key.soundCloudClientId) ?? "").isEmpty
                    && !(defaults.string(forKey: Key.soundCloudSecret) ?? "").isEmpty,
                soundCloudAuthenticated: !(defaults.string(forKey: Key.soundCloudAccessToken) ?? "").isEmpty
            )
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

    static func resetPreferences(
        defaults: UserDefaults = .standard,
        resetAnalysisPreferences: Bool = true
    ) {
        defaults.set("system", forKey: Key.appearanceMode)
        defaults.set(true, forKey: Key.hapticFeedbackEnabled)
        defaults.set(true, forKey: Key.autoLockEnabled)
        defaults.set(1.0, forKey: Key.userFrequencyMultiplier)
        defaults.set(3, forKey: Key.countdownDuration)
        defaults.set(false, forKey: Key.listeningHistoryEnabled)

        let retiredKeys = [
            Key.sessionNotifications,
            Key.breathingGuidanceEnabled,
            Key.defaultIntensity,
            Key.preferredSessionDuration,
            Key.bilateralModeDefault,
            Key.audioQualityRaw,
            Key.displayBrightness,
            Key.keepScreenOn,
            Key.analyticsEnabled
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
        resetAnalysisPreferences: Bool = true,
        clearSharedHistory: Bool = true
    ) throws {
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

    private static func audioLibrary(defaults: UserDefaults) -> ExportAudioLibrary {
        guard
            let data = defaults.data(forKey: Key.audioFiles),
            let files = try? JSONDecoder().decode([AudioFile].self, from: data)
        else {
            return ExportAudioLibrary(fileCount: 0, fileNames: [])
        }

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
