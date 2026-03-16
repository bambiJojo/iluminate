//
//  SessionHistoryManager.swift
//  Ilumionate
//
//  Persistent session history and listening statistics.
//

import Foundation
import Observation

// MARK: - Session History Entry

struct SessionHistoryEntry: Codable, Identifiable {
    let id: UUID
    let sessionName: String
    let category: String
    let date: Date
    let durationListened: TimeInterval
    let totalDuration: TimeInterval
    let completed: Bool

    var completionFraction: Double {
        guard totalDuration > 0 else { return 0 }
        return min(1.0, durationListened / totalDuration)
    }
}

// MARK: - Session History Manager

@MainActor
@Observable
final class SessionHistoryManager {

    static let shared = SessionHistoryManager()

    private(set) var entries: [SessionHistoryEntry] = []

    private let storageKey = "sessionHistory_v1"

    private init() {
        load()
    }

    // MARK: - Recording

    /// Records a listening session. Ignored if `durationListened` is under 30 seconds
    /// or if the user has opted out of session history tracking.
    func record(
        sessionName: String,
        category: String,
        durationListened: TimeInterval,
        totalDuration: TimeInterval
    ) {
        guard UserDefaults.standard.bool(forKey: "listeningHistoryEnabled") else { return }
        guard durationListened >= 30 else { return }
        let completed = totalDuration > 0 && (durationListened / totalDuration) >= 0.95
        let entry = SessionHistoryEntry(
            id: UUID(),
            sessionName: sessionName,
            category: category,
            date: Date(),
            durationListened: durationListened,
            totalDuration: totalDuration,
            completed: completed
        )
        entries.insert(entry, at: 0)
        if entries.count > 100 {
            entries = Array(entries.prefix(100))
        }
        save()
    }

    func clearHistory() {
        entries = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Computed Statistics

    var totalSessionsCompleted: Int {
        entries.filter(\.completed).count
    }

    var totalListeningTime: TimeInterval {
        entries.reduce(0) { $0 + $1.durationListened }
    }

    /// Consecutive calendar days (ending today) with at least one session.
    var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        let daySet = Set(entries.map { calendar.startOfDay(for: $0.date) })
        while daySet.contains(checkDate) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previous
        }
        return streak
    }

    /// Sessions per day for the last 7 days. Index 0 = 6 days ago, index 6 = today.
    func weeklyActivity() -> [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { daysAgo in
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return 0 }
            return entries.filter { calendar.startOfDay(for: $0.date) == day }.count
        }
    }

    var thisWeekSessionCount: Int {
        weeklyActivity().reduce(0, +)
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([SessionHistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }
}
