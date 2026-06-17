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
    let segments: [TranceScriptSegment]
}
