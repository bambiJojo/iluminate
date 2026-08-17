//
//  HomeDoor.swift
//  Ilumionate
//
//  The four doors on the launcher home screen.
//
//  Fixed order, equal weight, never reordered by usage. The app has four parts
//  people care about — reader, audio, hypnotic visuals, light entrainment — and
//  home's job is to show all four rather than guess which one someone wants.
//  Audio analysis and synced playback are one door, not two: they are a single
//  pipeline, and splitting them would only make people guess which to tap.
//

import SwiftUI

/// Where a door sends you. `create` carries the segment to preselect.
enum HomeDoorRoute: Equatable, Sendable {
    case library
    case reader
    case create(CreateSessionKind)
}

enum HomeDoor: String, CaseIterable, Identifiable, Sendable {
    case listen
    case read
    case visuals
    case pulse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listen:  "Listen"
        case .read:    "Read"
        case .visuals: "Visuals"
        case .pulse:   "Pulse"
        }
    }

    var subtitle: String {
        switch self {
        case .listen:  "Your audio, light-synced"
        case .read:    "Scripts, paced"
        case .visuals: "A wordless field"
        case .pulse:   "Flash entrainment"
        }
    }

    var systemImage: String {
        switch self {
        case .listen:  "waveform"
        case .read:    "text.aligncenter"
        case .visuals: "circle.hexagonpath.fill"
        case .pulse:   "lightbulb.fill"
        }
    }

    var tint: Color {
        switch self {
        case .listen:  .bwAlpha
        case .read:    .roseGold
        case .visuals: .bwGamma
        case .pulse:   .bwBeta
        }
    }

    /// The light path lands on Create with its segment selected rather than
    /// starting a session, so `CreateSessionKind.requiresSafetyWarning` still
    /// gates the flash.
    var route: HomeDoorRoute {
        switch self {
        case .listen:  .library
        case .read:    .reader
        case .visuals: .create(.visualField)
        case .pulse:   .create(.flash)
        }
    }

    /// `listen` keeps the `audioLibrary` wire value even though it now opens the
    /// Library tab. The case identifies *which door was tapped*, and renaming it
    /// would split the metric in two at the point the destination changed.
    var analyticsAction: HomeCoreAction {
        switch self {
        case .listen:  .audioLibrary
        case .read:    .reader
        case .visuals: .visuals
        case .pulse:   .pulse
        }
    }
}
