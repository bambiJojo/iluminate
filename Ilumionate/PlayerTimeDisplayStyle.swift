//
//  PlayerTimeDisplayStyle.swift
//  Ilumionate
//
//  How the player reports progress through a file. Tapping the time label
//  cycles the style, and the choice persists across sessions.
//

import Foundation

enum PlayerTimeDisplayStyle: String, CaseIterable, Sendable {
    /// "12:34 / 45:00"
    case elapsed
    /// "−32:26"
    case remaining
    /// "27%"
    case percentage

    /// Reads a stored preference, treating a missing or unknown value as `.elapsed`.
    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .elapsed
    }

    var next: PlayerTimeDisplayStyle {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? all.startIndex
        return all[(index + 1) % all.count]
    }

    /// Short name for the accessibility hint, describing what the label shows.
    var displayName: String {
        switch self {
        case .elapsed: "Elapsed time"
        case .remaining: "Time remaining"
        case .percentage: "Percent complete"
        }
    }

    /// The label text. With no known length (live or open-ended modes) every
    /// style falls back to plain elapsed time, since there is nothing to count
    /// down from.
    func text(
        currentTime: TimeInterval,
        duration: TimeInterval,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let current = Self.sanitized(currentTime)
        let total = Self.sanitized(duration)
        guard total > 0 else { return Self.clock(current) }

        let position = min(current, total)
        switch self {
        case .elapsed:
            return Self.clock(position) + " / " + Self.clock(total)
        case .remaining:
            return "\u{2212}" + Self.clock(total - position)
        case .percentage:
            // Round down so "100%" only appears once the file has ended.
            let percent = (position / total * 100).rounded(.down) / 100
            return percent.formatted(.percent.precision(.fractionLength(0)).locale(locale))
        }
    }

    /// "4:05", or "1:02:05" once an hour is reached.
    static func clock(_ seconds: TimeInterval) -> String {
        let seconds = sanitized(seconds)
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600
            ? .hourMinuteSecond
            : .minuteSecond
        return Duration.seconds(seconds).formatted(.time(pattern: pattern))
    }

    private static func sanitized(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite ? max(0, seconds) : 0
    }
}
