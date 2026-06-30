//  TranceScript.swift
//  Ilumionate
//
//  Data model for a Text Trance reading script: phase-structured plain-text
//  segments plus metadata. Loaded from bundled JSON, paced at runtime.

import Foundation

/// Which session arc a script (or segment) supports.
enum ScriptArc: String, Codable, Sendable, CaseIterable, Identifiable {
    case fullText   // eyes-open from induction through read emergence
    case handoff    // text inducts, then eyes close; light/binaural finish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullText: return "Read everything"
        case .handoff:  return "Read, then eyes close"
        }
    }
}

/// High-level intent of a script. Distinct from `TrancePhase` (which is
/// per-segment). Drives the library theme filter.
enum ScriptTheme: String, Codable, Sendable, CaseIterable, Identifiable {
    case relaxation
    case sleep
    case focus
    case suggestion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relaxation: return "Relaxation"
        case .sleep:      return "Sleep"
        case .focus:      return "Focus"
        case .suggestion: return "Self-Suggestion"
        }
    }
}

/// Provenance + review status of a script's content.
struct ScriptSource: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case bundled
        case generated
        case importedWeb
    }
    let kind: Kind
    let generator: String?
    let reviewed: Bool
}

/// Per-segment pacing hint. `baseWPM` is a target words-per-minute the engine
/// multiplies by the user speed setting; never a hard timing.
struct SegmentPacing: Codable, Sendable, Equatable {
    let baseWPM: Double
}

/// One phase-tagged chunk of script text.
struct TranceScriptSegment: Codable, Sendable {
    let phase: TrancePhase
    let text: String
    let pacing: SegmentPacing?
    /// Arcs this segment plays in. `nil` => plays in every arc.
    let arcs: [ScriptArc]?
    /// When true (handoff arc only), reaching the end of this segment ends the
    /// reading portion and triggers the light/binaural handoff tail.
    let triggersHandoff: Bool?
}

/// A complete Text Trance script.
struct TranceScript: Codable, Sendable, Identifiable {
    let schemaVersion: Int
    let id: String
    let title: String
    let theme: ScriptTheme
    let supportedArcs: [ScriptArc]
    let language: String
    let source: ScriptSource
    var summary: String? = nil
    let segments: [TranceScriptSegment]
}

struct TranceScriptMetrics: Equatable, Sendable {
    let arc: ScriptArc
    let wordCount: Int
    let estimatedDuration: TimeInterval
}

extension TranceScript {
    var librarySummary: String {
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return "\(theme.displayName) script with \(phaseSummary.lowercased()) pacing."
    }

    var arcSummary: String {
        let supportsFullText = supportedArcs.contains(.fullText)
        let supportsHandoff = supportedArcs.contains(.handoff)

        switch (supportsFullText, supportsHandoff) {
        case (true, true):   return "Read-through + handoff"
        case (true, false):  return "Read-through"
        case (false, true):  return "Handoff"
        case (false, false): return "No arc"
        }
    }

    var durationSummary: String {
        let minutes = metricsByArc.map { Self.roundedMinutes($0.estimatedDuration) }
        guard let min = minutes.min(), let max = minutes.max() else { return "No duration" }
        if min == max { return Self.minuteText(min) }
        return "\(min)-\(Self.minuteText(max))"
    }

    var wordCountSummary: String {
        let counts = metricsByArc.map(\.wordCount)
        guard let min = counts.min(), let max = counts.max() else { return "No words" }
        if min == max { return "\(min.formatted(.number)) words" }
        return "\(min.formatted(.number))-\(max.formatted(.number)) words"
    }

    var phaseSummary: String {
        var seen: Set<String> = []
        var names: [String] = []

        for segment in segments {
            let rawValue = segment.phase.rawValue
            guard seen.contains(rawValue) == false else { continue }
            seen.insert(rawValue)
            names.append(segment.phase.displayName)
        }

        let visibleNames = names.prefix(4)
        let suffix = names.count > visibleNames.count ? " +" : ""
        return visibleNames.joined(separator: ", ") + suffix
    }

    func metrics(for arc: ScriptArc) -> TranceScriptMetrics {
        let schedule = TextPacingEngine.schedule(
            for: self,
            settings: TextPacingSettings(
                arc: arc,
                speedMultiplier: 1.0,
                subliminalEnabled: false
            )
        )
        return TranceScriptMetrics(
            arc: arc,
            wordCount: schedule.count,
            estimatedDuration: schedule.reduce(0) { $0 + $1.duration }
        )
    }

    private var metricsByArc: [TranceScriptMetrics] {
        supportedArcs.map { metrics(for: $0) }
    }

    private static func roundedMinutes(_ duration: TimeInterval) -> Int {
        max(1, Int((duration / 60).rounded()))
    }

    private static func minuteText(_ minutes: Int) -> String {
        minutes == 1 ? "1 min" : "\(minutes) min"
    }
}
