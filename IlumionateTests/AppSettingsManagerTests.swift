//
//  AppSettingsManagerTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct AppSettingsManagerTests {
    @Test
    func exportSnapshot_writesStructuredJSON() async throws {
        let defaults = try makeDefaults()
        let exportDirectory = try makeDirectory()
        let libraryURL = exportDirectory.appending(path: "library.json")
        let storage = AudioLibraryStorage(fileURL: libraryURL, legacyDefaults: defaults)

        defaults.set("Byron", forKey: AppSettingsManager.Key.profileName)
        defaults.set("Sleep deeper", forKey: AppSettingsManager.Key.profileGoal)
        defaults.set("dark", forKey: AppSettingsManager.Key.appearanceMode)
        defaults.set(false, forKey: AppSettingsManager.Key.hapticFeedbackEnabled)
        defaults.set(false, forKey: AppSettingsManager.Key.autoLockEnabled)
        defaults.set(1.4, forKey: AppSettingsManager.Key.userFrequencyMultiplier)
        defaults.set(7, forKey: AppSettingsManager.Key.countdownDuration)
        defaults.set(true, forKey: AppSettingsManager.Key.listeningHistoryEnabled)

        let files = [
            AnalysisFixtures.audioFile(filename: "first.m4a"),
            AnalysisFixtures.audioFile(filename: "second.m4a")
        ]
        #expect(await AudioLibraryStore.save(files, storage: storage))

        let history = [
            SessionHistoryEntry(
                id: UUID(),
                sessionName: "Night Session",
                category: "Sleep",
                date: Date(timeIntervalSince1970: 0),
                durationListened: 120,
                totalDuration: 150,
                completed: false
            )
        ]
        defaults.set(try JSONEncoder().encode(history), forKey: AppSettingsManager.Key.sessionHistory)

        let analysisSnapshot = AnalysisPreferences.Snapshot(
            contentHint: .hypnosis,
            customInstructions: "Prefer warmer color temperatures.",
            intensityMultiplier: 0.8,
            frequencyProfile: .deep,
            transitionStyle: .fluid,
            colorTempMode: .warm,
            bilateralMode: true,
            autoAnalyzeOnImport: false
        )

        let exportURL = try await AppSettingsManager.exportSnapshot(
            defaults: defaults,
            exportDirectory: exportDirectory,
            audioLibraryStorage: storage,
            analysisPreferencesSnapshot: analysisSnapshot
        )

        let data = try Data(contentsOf: exportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AppSettingsManager.ExportSnapshot.self, from: data)

        #expect(snapshot.profile.name == "Byron")
        #expect(snapshot.settings.appearanceMode == "dark")
        #expect(snapshot.settings.keepScreenAwakeDuringSessions == false)
        #expect(snapshot.audioLibrary.fileCount == 2)
        #expect(snapshot.sessionHistory.count == 1)
        #expect(snapshot.analysisPreferences.customInstructions.contains("warmer"))
    }

    @Test
    func resetPreferences_restoresDefaultsAndRemovesRetiredKeys() throws {
        let defaults = try makeDefaults()

        defaults.set("dark", forKey: AppSettingsManager.Key.appearanceMode)
        defaults.set(false, forKey: AppSettingsManager.Key.hapticFeedbackEnabled)
        defaults.set(false, forKey: AppSettingsManager.Key.autoLockEnabled)
        defaults.set(1.7, forKey: AppSettingsManager.Key.userFrequencyMultiplier)
        defaults.set(10, forKey: AppSettingsManager.Key.countdownDuration)
        defaults.set(true, forKey: AppSettingsManager.Key.listeningHistoryEnabled)
        defaults.set(true, forKey: AppSettingsManager.Key.analyticsEnabled)
        defaults.set(true, forKey: AppSettingsManager.Key.analyticsConsentGranted)
        defaults.set(true, forKey: AppSettingsManager.Key.analyticsConsentAnswered)
        defaults.set(Date(), forKey: AppSettingsManager.Key.analyticsActivationStart)
        defaults.set(true, forKey: AppSettingsManager.Key.analyticsActivationCompleted)
        defaults.set(0.7, forKey: AppSettingsManager.Key.defaultIntensity)

        AppSettingsManager.resetPreferences(
            defaults: defaults,
            resetAnalysisPreferences: false
        )

        #expect(defaults.string(forKey: AppSettingsManager.Key.appearanceMode) == "system")
        #expect(defaults.bool(forKey: AppSettingsManager.Key.hapticFeedbackEnabled))
        #expect(defaults.bool(forKey: AppSettingsManager.Key.autoLockEnabled))
        #expect(defaults.double(forKey: AppSettingsManager.Key.userFrequencyMultiplier) == 1.0)
        #expect(defaults.integer(forKey: AppSettingsManager.Key.countdownDuration) == 3)
        #expect(defaults.bool(forKey: AppSettingsManager.Key.listeningHistoryEnabled) == false)
        #expect(defaults.object(forKey: AppSettingsManager.Key.analyticsEnabled) == nil)
        #expect(defaults.object(forKey: AppSettingsManager.Key.analyticsConsentGranted) == nil)
        #expect(defaults.object(forKey: AppSettingsManager.Key.analyticsConsentAnswered) == nil)
        #expect(defaults.object(forKey: AppSettingsManager.Key.analyticsActivationStart) == nil)
        #expect(defaults.object(forKey: AppSettingsManager.Key.analyticsActivationCompleted) == nil)
        #expect(defaults.object(forKey: AppSettingsManager.Key.defaultIntensity) == nil)
    }

    @Test
    func clearAllData_removesStoredContentAndDocuments() async throws {
        let defaults = try makeDefaults()
        let documentsDirectory = try makeDirectory()
        let applicationSupportDirectory = try makeDirectory()
        let libraryDirectory = try makeDirectory()
        let libraryURL = libraryDirectory.appending(path: "library.json")
        let storage = AudioLibraryStorage(fileURL: libraryURL, legacyDefaults: defaults)
        let markerURL = documentsDirectory.appending(path: "marker.txt")
        try Data("marker".utf8).write(to: markerURL, options: .atomic)
        try Data("private".utf8).write(
            to: applicationSupportDirectory.appending(path: "private-marker.txt"),
            options: .atomic
        )
        #expect(
            await AudioLibraryStore.save(
                [AnalysisFixtures.audioFile(filename: "first.m4a")],
                storage: storage
            )
        )

        defaults.set("Byron", forKey: AppSettingsManager.Key.profileName)
        defaults.set("goal", forKey: AppSettingsManager.Key.profileGoal)
        defaults.set(Data(), forKey: AppSettingsManager.Key.audioFiles)
        defaults.set(Data(), forKey: AppSettingsManager.Key.sessionHistory)
        defaults.set(true, forKey: AppSettingsManager.Key.hasCompletedOnboarding)
        defaults.set("client", forKey: AppSettingsManager.Key.soundCloudClientId)
        defaults.set("cached", forKey: "\(AppSettingsManager.Key.streamingTrackPrefix)test")

        try await AppSettingsManager.clearAllData(
            defaults: defaults,
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            audioLibraryStorage: storage,
            resetAnalysisPreferences: false,
            clearSharedHistory: false
        )

        #expect(defaults.object(forKey: AppSettingsManager.Key.profileName) == nil)
        #expect(defaults.object(forKey: AppSettingsManager.Key.audioFiles) == nil)
        #expect(defaults.object(forKey: AppSettingsManager.Key.sessionHistory) == nil)
        #expect(defaults.object(forKey: AppSettingsManager.Key.soundCloudClientId) == nil)
        #expect(defaults.object(forKey: "\(AppSettingsManager.Key.streamingTrackPrefix)test") == nil)
        #expect(defaults.bool(forKey: AppSettingsManager.Key.hapticFeedbackEnabled))
        #expect(defaults.string(forKey: AppSettingsManager.Key.appearanceMode) == "system")

        let remainingItems = try FileManager.default.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(remainingItems.isEmpty)
        #expect(FileManager.default.fileExists(atPath: applicationSupportDirectory.path()) == false)
        #expect(FileManager.default.fileExists(atPath: libraryURL.path()) == false)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "AppSettingsManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.defaultsCreationFailed
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private enum TestError: Error {
        case defaultsCreationFailed
    }
}

/// The streaming feature was removed in `e9cb0f1`, but removing the code that
/// reads a credential does not remove the credential. A device that authenticated
/// with SoundCloud before then still holds the client secret and OAuth token in
/// `UserDefaults` — a plist in the app container, included in device backups.
/// See ERRORS.md ERR-020.
@MainActor
struct RetiredStreamingCredentialTests {

    @Test("Credentials left by the retired streaming feature are purged")
    func purgesRetiredStreamingCredentials() throws {
        let suiteName = "retired-streaming-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("client", forKey: AppSettingsManager.Key.soundCloudClientId)
        defaults.set("secret", forKey: AppSettingsManager.Key.soundCloudSecret)
        defaults.set("token", forKey: AppSettingsManager.Key.soundCloudAccessToken)

        AppSettingsManager.purgeRetiredStreamingCredentials(defaults: defaults)

        #expect(defaults.string(forKey: AppSettingsManager.Key.soundCloudClientId) == nil)
        #expect(defaults.string(forKey: AppSettingsManager.Key.soundCloudSecret) == nil)
        #expect(defaults.string(forKey: AppSettingsManager.Key.soundCloudAccessToken) == nil)
    }

    /// It runs on every launch, so the overwhelmingly common case is that there is
    /// nothing to remove.
    @Test("Purging is safe when no credentials were ever stored")
    func purgeIsSafeWhenNothingStored() throws {
        let suiteName = "retired-streaming-empty-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppSettingsManager.purgeRetiredStreamingCredentials(defaults: defaults)

        #expect(defaults.string(forKey: AppSettingsManager.Key.soundCloudAccessToken) == nil)
    }
}
