//
//  LightScoreReader.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/9/26.
//

import Foundation

/// Loads and validates LightSession files from JSON.
/// Supports both bundled resources and imported files.
class LightScoreReader {

    enum ReaderError: LocalizedError {
        case fileNotFound(String)
        case invalidJSON(String)
        case invalidSessionData(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let name):
                return "Session file not found: \(name)"
            case .invalidJSON(let detail):
                return "Invalid JSON format: \(detail)"
            case .invalidSessionData(let detail):
                return "Invalid session data: \(detail)"
            }
        }
    }

    // MARK: - Loading from Bundle

    /// Load a session from a bundled JSON file
    static func loadSession(named fileName: String) throws -> LightSession {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            throw ReaderError.fileNotFound(fileName)
        }
        return try loadSession(from: url)
    }

    // MARK: - Loading from URL

    /// Load a session from any file URL
    static func loadSession(from url: URL) throws -> LightSession {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ReaderError.fileNotFound(url.lastPathComponent)
        }

        return try loadSession(from: data)
    }

    // MARK: - Loading from Data

    /// Load a session from raw JSON data
    static func loadSession(from data: Data) throws -> LightSession {
        let decoder = JSONDecoder()

        let session: LightSession
        do {
            session = try decoder.decode(LightSession.self, from: data)
        } catch {
            throw ReaderError.invalidJSON(error.localizedDescription)
        }

        // Validate session data
        try validate(session: session)

        return session
    }

    // MARK: - Validation

    /// Validates that a session has valid data
    private static func validate(session: LightSession) throws {
        // Check duration is positive
        guard session.duration_sec > 0 else {
            throw ReaderError.invalidSessionData("Duration must be positive")
        }

        // Check that light score is not empty
        guard !session.light_score.isEmpty else {
            throw ReaderError.invalidSessionData("Light score cannot be empty")
        }

        // Validate each moment
        for (index, moment) in session.light_score.enumerated() {
            // Time must be within session duration
            guard moment.time >= 0 && moment.time <= session.duration_sec else {
                throw ReaderError.invalidSessionData("Moment \(index) time (\(moment.time)s) is outside session duration")
            }

            // Frequency must be reasonable
            guard moment.frequency >= 0.1 && moment.frequency <= 100.0 else {
                throw ReaderError.invalidSessionData("Moment \(index) frequency (\(moment.frequency) Hz) is out of valid range (0.1-100 Hz)")
            }

            // Intensity must be 0-1
            guard moment.intensity >= 0.0 && moment.intensity <= 1.0 else {
                throw ReaderError.invalidSessionData("Moment \(index) intensity (\(moment.intensity)) must be between 0.0 and 1.0")
            }
        }

        // Check that moments are sorted by time
        let sortedMoments = session.light_score.sorted { $0.time < $1.time }
        let isSorted = zip(session.light_score, sortedMoments).allSatisfy { $0.time == $1.time }

        if !isSorted {
            throw ReaderError.invalidSessionData("Light score moments must be sorted by time")
        }
    }

    // MARK: - Discovery

    /// Returns all bundled session files found in the app bundle
    static func discoverBundledSessions() -> [String] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            return []
        }

        return urls.compactMap { url in
            // Try to load and validate the session
            guard let _ = try? loadSession(from: url) else { return nil }
            return url.deletingPathExtension().lastPathComponent
        }
    }
}
