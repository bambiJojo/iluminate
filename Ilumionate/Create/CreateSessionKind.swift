//  CreateSessionKind.swift
//  Ilumionate
//
//  What the Create tab is making. This is the segmented row at the top of the
//  screen, and it decides which tiles the tray shows.
//
//  `visualField` is the odd one out and deliberately so: it never touches
//  LightEngine or FlashController, which is why it carries no photosensitivity
//  warning. Keeping that warning on the light path preserves its meaning —
//  showing it everywhere teaches people to dismiss it.

import Foundation

enum CreateSessionKind: String, CaseIterable, Identifiable, Sendable {
    case flash
    case colourPulse
    case bilateral
    case visualField

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flash:       return "Flash"
        case .colourPulse: return "Colour"
        case .bilateral:   return "Bilateral"
        case .visualField: return "Visuals"
        }
    }

    var systemImage: String {
        switch self {
        case .flash:       return "flashlight.on.fill"
        case .colourPulse: return "paintpalette.fill"
        case .bilateral:   return "circle.lefthalf.filled"
        case .visualField: return "circle.hexagonpath.fill"
        }
    }

    var summary: String {
        switch self {
        case .flash:       return "Full-screen flashing pattern"
        case .colourPulse: return "Slow colour breathing"
        case .bilateral:   return "Independent left and right fields"
        case .visualField: return "A wordless hypnotic field"
        }
    }

    /// Whether this kind drives LightEngine / FlashController.
    var usesLightEngine: Bool {
        self != .visualField
    }

    /// Only the light path flashes, so only the light path warns.
    var requiresSafetyWarning: Bool {
        usesLightEngine
    }

    // MARK: - Analytics

    var analyticsMode: CreateMode {
        switch self {
        case .flash:       return .flash
        case .colourPulse: return .colorPulse
        case .bilateral:   return .bilateral
        case .visualField: return .visualField
        }
    }

    var mindMachineMode: MindMachineMode {
        switch self {
        case .flash:       return .flash
        case .colourPulse: return .colorPulse
        case .bilateral:   return .bilateral
        case .visualField: return .visualField
        }
    }
}

// MARK: - Start bar copy

extension CreateSessionKind {

    func startTitle(binauralEnabled: Bool) -> String {
        switch self {
        case .visualField: return "Begin Visuals"
        case .colourPulse: return "Start Colour Pulse"
        case .bilateral:
            return binauralEnabled ? "Start Bilateral + Binaural" : "Start Bilateral Flash"
        case .flash:
            return binauralEnabled ? "Start Flash + Binaural" : "Start Flash Session"
        }
    }

    func startIcon(binauralEnabled: Bool) -> String {
        switch self {
        case .visualField: return "play.fill"
        case .colourPulse: return "paintpalette.fill"
        case .flash, .bilateral:
            return binauralEnabled ? "headphones" : "play.fill"
        }
    }
}
