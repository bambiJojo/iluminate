//
//  PlayerMode.swift
//  Ilumionate
//
//  Defines all playback modes for the unified player and their capability flags.
//

import Foundation

// MARK: - Light Sync Status

/// Analysis-aware status for audio mode light sync toggle.
enum LightSyncStatus {
    case enabled
    case ready
    case analyzing(progress: Double, stage: String)
    case queued(position: Int)
    case unavailable
}

// MARK: - Player Mode

/// All playback modes supported by the unified player.
enum PlayerMode: Identifiable {
    case session(session: LightSession, audioFile: AudioFile?)
    case flashMode(
        frequency: Double,
        intensity: Double,
        colorTemperature: Int,
        pattern: MindMachineModel.LightPattern,
        binauralEnabled: Bool,
        binauralCarrier: Double,
        binauralVolume: Double
    )
    case colorPulse(frequency: Double, intensity: Double)
    case audioLight(audioFile: AudioFile)
    case playlist(playlist: Playlist)

    var id: String {
        switch self {
        case .session(let session, _):
            return "session-\(session.id)"
        case .flashMode:
            return "flash-\(UUID())"
        case .colorPulse:
            return "colorPulse-\(UUID())"
        case .audioLight(let file):
            return "audio-\(file.id)"
        case .playlist(let playlist):
            return "playlist-\(playlist.id)"
        }
    }

    // MARK: - Display

    var title: String {
        switch self {
        case .session(let session, _):
            return session.displayName
        case .flashMode:
            return "Mind Machine"
        case .colorPulse:
            return "Color Pulse"
        case .audioLight(let file):
            return file.displayName
        case .playlist(let playlist):
            return playlist.name
        }
    }

    // MARK: - Capability Flags

    var hasAudioScrubber: Bool {
        switch self {
        case .session, .audioLight, .playlist: return true
        case .flashMode, .colorPulse: return false
        }
    }

    var hasVolumeControl: Bool {
        switch self {
        case .audioLight, .playlist: return true
        case .session(_, let audioFile): return audioFile != nil
        case .flashMode, .colorPulse: return false
        }
    }

    var hasBrightnessControl: Bool {
        switch self {
        case .session, .playlist: return true
        case .audioLight: return true // shown when light sync enabled
        case .flashMode, .colorPulse: return false
        }
    }

    var hasSkipControls: Bool {
        switch self {
        case .audioLight: return true
        case .playlist: return true
        case .session, .flashMode, .colorPulse: return false
        }
    }

    var hasTrackNavigation: Bool {
        switch self {
        case .playlist: return true
        default: return false
        }
    }

    var hasLightSyncToggle: Bool {
        switch self {
        case .audioLight: return true
        default: return false
        }
    }

    var hasBilateralToggle: Bool {
        switch self {
        case .flashMode: return true
        default: return false
        }
    }

    var hasBinauralToggle: Bool {
        switch self {
        case .flashMode: return true
        default: return false
        }
    }

    var hasDriftControl: Bool {
        switch self {
        case .flashMode: return true
        default: return false
        }
    }

    var hasTrackList: Bool {
        switch self {
        case .playlist: return true
        default: return false
        }
    }

    var hasPhaseIndicator: Bool {
        switch self {
        case .session: return true
        default: return false
        }
    }

    var hasMandalaVisualizer: Bool {
        switch self {
        case .session: return true
        default: return false
        }
    }

    var requiresSafetyWarning: Bool {
        switch self {
        case .flashMode, .colorPulse: return true
        default: return false
        }
    }

    /// Whether this mode uses a dark visual (flash/color/light engine backgrounds)
    var usesDarkChrome: Bool {
        switch self {
        case .flashMode, .colorPulse, .playlist: return true
        case .audioLight: return false // switches when light sync enabled
        case .session: return false
        }
    }

    /// Whether this mode has a finite duration (vs infinite like flash/color pulse)
    var hasFiniteDuration: Bool {
        switch self {
        case .session, .audioLight, .playlist: return true
        case .flashMode, .colorPulse: return false
        }
    }

    var hasFrequencyDisplay: Bool {
        switch self {
        case .flashMode, .colorPulse: return true
        default: return false
        }
    }

    var hasSyncOptions: Bool {
        switch self {
        case .session(_, let audioFile): return audioFile != nil
        default: return false
        }
    }

    var hasSmartTransitions: Bool {
        switch self {
        case .playlist: return true
        default: return false
        }
    }
}
