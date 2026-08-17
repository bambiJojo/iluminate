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
        binauralVolume: Double,
        goalDuration: TimeInterval? = nil
    )
    case colorPulse(frequency: Double, intensity: Double)
    /// A wordless shader field. Never drives LightEngine or FlashController,
    /// which is why it carries no photosensitivity warning.
    case visualField(
        settings: VisualFieldSettings,
        audioFile: AudioFile?,
        binaural: BinauralSettings?
    )
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
        case .visualField:
            return "visualField-\(UUID())"
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
        case .visualField:
            return "Visual Field"
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
        case .visualField(_, let audioFile, _): return audioFile != nil
        case .flashMode, .colorPulse: return false
        }
    }

    var hasVolumeControl: Bool {
        switch self {
        case .audioLight, .playlist: return true
        case .session(_, let audioFile): return audioFile != nil
        case .visualField(_, let audioFile, _): return audioFile != nil
        case .flashMode, .colorPulse: return false
        }
    }

    var hasBrightnessControl: Bool {
        switch self {
        case .session, .playlist: return true
        case .audioLight: return true // shown when light sync enabled
        // Strength is the field's own knob, and the field does not drive the
        // light engine that screen brightness would scale.
        case .visualField: return false
        case .flashMode, .colorPulse: return false
        }
    }

    var hasSkipControls: Bool {
        switch self {
        case .audioLight: return true
        case .playlist: return true
        case .session, .flashMode, .colorPulse, .visualField: return false
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
        case .session(let session, _): return session.binaural_enabled
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
        return false
    }

    /// Whether the player counts down and begins as soon as it appears,
    /// rather than opening idle and waiting for the transport's play button.
    ///
    /// True only for the visual field. Its background is a shader that renders
    /// whenever it is on screen, so an idle player over a moving field reads as
    /// a broken paused state — the session must start when the screen does.
    var beginsAutomatically: Bool {
        switch self {
        case .visualField: return true
        default: return false
        }
    }

    /// The instruction shown while the session opens.
    ///
    /// Reads as a standalone sentence because the threshold has no numerals
    /// for it to lead into. It still sits above the count on the VoiceOver
    /// fallback, where "Close your eyes and relax" followed by "3" is fine.
    var countdownIntroMessage: String {
        switch self {
        case .visualField: return "Soften your gaze"
        default: return "Close your eyes and relax"
        }
    }

    /// The line held on screen after the count, or nil to begin immediately.
    ///
    /// Nil for the visual field: it is watched, not listened to with eyes
    /// shut, so "Close your eyes" would be an instruction to miss the session.
    var countdownHoldMessage: String? {
        switch self {
        case .visualField: return nil
        default: return "Close your eyes"
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
        case .flashMode, .colorPulse, .playlist, .visualField: return true
        case .audioLight: return false // switches when light sync enabled
        case .session: return false
        }
    }

    /// Whether this mode has a finite duration (vs infinite like flash/color pulse)
    var hasFiniteDuration: Bool {
        switch self {
        case .session, .audioLight, .playlist:
            return true
        case .flashMode(_, _, _, _, _, _, _, let goalDuration):
            return goalDuration != nil
        case .visualField(let settings, _, _):
            return settings.duration != nil
        case .colorPulse:
            return false
        }
    }

    /// Optional finish line for quick Mind Machine presets. Custom sessions
    /// remain open-ended when no goal is supplied.
    var goalDuration: TimeInterval? {
        switch self {
        case .flashMode(_, _, _, _, _, _, _, let goalDuration):
            return goalDuration
        case .visualField(let settings, _, _):
            return settings.duration
        default:
            return nil
        }
    }

    var hasFrequencyDisplay: Bool {
        switch self {
        case .flashMode, .colorPulse: return true
        default: return false
        }
    }

    /// Whether this mode can drop to audio-only playback. True for the modes
    /// that drive the light engine alongside audio; `.audioLight` is excluded
    /// because it has its own Light Sync control.
    var hasMindMachineToggle: Bool {
        switch self {
        case .session(_, let audioFile): return audioFile != nil
        case .playlist: return true
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
