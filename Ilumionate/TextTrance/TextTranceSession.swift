//  TextTranceSession.swift
//  Ilumionate
//
//  Observable coordinator for a running Text Trance session. Drives the RSVP
//  word stream from the pacing schedule and orchestrates the optional light /
//  binaural layers across the arc (reading -> optional handoff tail -> done).

import Foundation

/// Everything the player needs to run one session.
struct TextTranceSessionSettings: Sendable {
    let arc: ScriptArc
    let speed: TextPacingSettings.Speed
    let lightEnabled: Bool
    let binauralEnabled: Bool
    let beatFrequency: Double
    let postHandoffDuration: TimeInterval
    let subliminalEnabled: Bool
    let subliminalSpeed: TextPacingSettings.SubliminalSpeed

    init(arc: ScriptArc,
         speed: TextPacingSettings.Speed,
         lightEnabled: Bool,
         binauralEnabled: Bool,
         beatFrequency: Double,
         postHandoffDuration: TimeInterval,
         subliminalEnabled: Bool = true,
         subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium) {
        self.arc = arc
        self.speed = speed
        self.lightEnabled = lightEnabled
        self.binauralEnabled = binauralEnabled
        self.beatFrequency = beatFrequency
        self.postHandoffDuration = postHandoffDuration
        self.subliminalEnabled = subliminalEnabled
        self.subliminalSpeed = subliminalSpeed
    }
}

@MainActor
@Observable
final class TextTranceSession {

    // Rendered state
    private(set) var currentWord: String = ""
    private(set) var currentPivotIndex: Int = 0
    private(set) var currentPhase: TrancePhase = .preTalk
    private(set) var isReading = false
    private(set) var lightActive = false
    private(set) var isComplete = false
    private(set) var currentFade: FadeKind = .none
    private(set) var currentDuration: TimeInterval = 0

    let script: TranceScript
    let settings: TextTranceSessionSettings
    let readerReferenceCharacterCount: Int

    private let light: (any LightLayerControlling)?
    private let audio: (any AudioLayerControlling)?
    private let sleep: @Sendable (Duration) async -> Void
    private var cancelled = false
    private var isRunning = false

    init(script: TranceScript,
         settings: TextTranceSessionSettings,
         light: (any LightLayerControlling)?,
         audio: (any AudioLayerControlling)?,
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.script = script
        self.settings = settings
        self.readerReferenceCharacterCount = TextTranceWordSizing.referenceCharacterCount(
            for: TextPacingEngine.schedule(
                for: script,
                settings: TextPacingSettings(arc: settings.arc,
                                             speed: settings.speed,
                                             subliminalEnabled: settings.subliminalEnabled,
                                             subliminalSpeed: settings.subliminalSpeed)
            )
        )
        self.light = light
        self.audio = audio
        self.sleep = sleep
    }

    /// Run the full session to completion (or until `end()` cancels it).
    func begin() async {
        guard !cancelled, !isComplete, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let pacing = TextPacingSettings(arc: settings.arc,
                                        speed: settings.speed,
                                        subliminalEnabled: settings.subliminalEnabled,
                                        subliminalSpeed: settings.subliminalSpeed)
        let schedule = TextPacingEngine.schedule(for: script, settings: pacing)

        if settings.binauralEnabled, let audio {
            audio.syncBeatFrequency(to: settings.beatFrequency)
            audio.start()
        }

        isReading = true
        for word in schedule {
            guard !cancelled, !Task.isCancelled else { break }
            currentWord = word.text
            currentPivotIndex = word.pivotIndex
            currentPhase = word.phase
            currentFade = word.fade
            currentDuration = word.duration
            await sleep(.seconds(word.duration))
        }
        isReading = false

        if settings.arc == .handoff, !cancelled, !Task.isCancelled {
            if settings.lightEnabled, let light {
                light.start()
                lightActive = true
            }
            await sleep(.seconds(settings.postHandoffDuration))
            if lightActive {
                light?.stop()
                lightActive = false
            }
        }

        if settings.binauralEnabled { audio?.stop() }
        isComplete = !cancelled && !Task.isCancelled
    }

    /// Stop everything immediately (user tap-and-hold to end).
    func end() {
        guard !isComplete else { return }
        cancelled = true
        if lightActive {
            light?.stop()
            lightActive = false
        }
        if settings.binauralEnabled { audio?.stop() }
        isReading = false
    }
}
