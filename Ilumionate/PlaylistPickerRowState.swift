//
//  PlaylistPickerRowState.swift
//  Ilumionate
//
//  What a single row in the playlist session picker is offering the user.
//
//  This exists because the picker used to have a dead end: a file with no
//  generated light session was listed, greyed out, and disabled, so tapping it
//  did nothing and said nothing. A tester read that as "my imports didn't
//  save". Every case here either acts, or explains itself.
//

import Foundation

enum PlaylistPickerRowState: String, CaseIterable, Equatable, Sendable {
    /// Has a generated light session — can be picked.
    case ready
    /// Already part of this playlist.
    case alreadyAdded
    /// Analysis is queued or running; the row resolves itself shortly.
    case analyzing
    /// No session yet — tapping starts analysis.
    case needsAnalysis

    /// Order matters. Membership of the playlist is the strongest signal, and
    /// an existing session outranks an in-flight re-analysis so a usable row
    /// never regresses to unusable mid-session.
    static func resolve(
        hasGeneratedSession: Bool,
        isAlreadyAdded: Bool,
        isAnalyzing: Bool
    ) -> Self {
        if isAlreadyAdded { return .alreadyAdded }
        if hasGeneratedSession { return .ready }
        if isAnalyzing { return .analyzing }
        return .needsAnalysis
    }

    /// Only a ready row can be checked and counted into "Add N Sessions".
    var isSelectable: Bool { self == .ready }

    /// Only a row with nothing in flight should start new work.
    var canStartAnalysis: Bool { self == .needsAnalysis }

    /// Trailing badge copy. `nil` where the row uses an icon instead.
    var badgeTitle: String? {
        switch self {
        case .ready, .alreadyAdded: return nil
        case .analyzing:            return "Analyzing…"
        case .needsAnalysis:        return "Tap to analyze"
        }
    }
}
