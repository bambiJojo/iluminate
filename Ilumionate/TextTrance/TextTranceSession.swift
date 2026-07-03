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
    let speedMultiplier: Double
    let lightEnabled: Bool
    let binauralEnabled: Bool
    let beatFrequency: Double
    let postHandoffDuration: TimeInterval
    let subliminalEnabled: Bool
    let subliminalSpeed: TextPacingSettings.SubliminalSpeed

    init(arc: ScriptArc,
         speedMultiplier: Double,
         lightEnabled: Bool,
         binauralEnabled: Bool,
         beatFrequency: Double,
         postHandoffDuration: TimeInterval,
         subliminalEnabled: Bool = true,
         subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium) {
        self.arc = arc
        self.speedMultiplier = speedMultiplier
        self.lightEnabled = lightEnabled
        self.binauralEnabled = binauralEnabled
        self.beatFrequency = beatFrequency
        self.postHandoffDuration = postHandoffDuration
        self.subliminalEnabled = subliminalEnabled
        self.subliminalSpeed = subliminalSpeed
    }

    /// Convenience for the legacy three presets (tests, anchors).
    init(arc: ScriptArc,
         speed: TextPacingSettings.Speed,
         lightEnabled: Bool,
         binauralEnabled: Bool,
         beatFrequency: Double,
         postHandoffDuration: TimeInterval,
         subliminalEnabled: Bool = true,
         subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium) {
        self.init(arc: arc, speedMultiplier: speed.multiplier,
                  lightEnabled: lightEnabled, binauralEnabled: binauralEnabled,
                  beatFrequency: beatFrequency, postHandoffDuration: postHandoffDuration,
                  subliminalEnabled: subliminalEnabled, subliminalSpeed: subliminalSpeed)
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

    // Control state
    private(set) var currentWordIndex = 0
    private(set) var isPaused = false
    var speedMultiplier: Double

    /// Reading progress by word position, 0…1. Drives the reader's progress line.
    var progressFraction: Double {
        schedule.isEmpty ? 0 : min(1, Double(currentWordIndex) / Double(schedule.count))
    }

    /// Total scheduled words (0 before `begin()` builds the schedule).
    var wordCount: Int { schedule.count }

    /// Phase of the scheduled word at `index`; nil out of range or pre-begin.
    func phase(atWordIndex index: Int) -> TrancePhase? {
        schedule.indices.contains(index) ? schedule[index].phase : nil
    }

    /// Reposition the word cursor (scrubbing). Renders the target word
    /// immediately; the playback loop continues from the new index. Pause
    /// state is left untouched — a paused session stays paused.
    func seek(toWordIndex index: Int) {
        guard isReading, !isComplete, !cancelled, !schedule.isEmpty else { return }
        currentWordIndex = min(max(index, 0), schedule.count - 1)
        render(schedule[currentWordIndex])
        seekRequested = true
        holdTask?.cancel()          // break any in-flight hold promptly
    }

    // Live, mutable copies of schedule-affecting settings.
    private(set) var subliminalEnabled: Bool
    private(set) var subliminalSpeed: TextPacingSettings.SubliminalSpeed
    private(set) var binauralActive: Bool
    private(set) var lightEnabledLive: Bool

    let script: TranceScript
    let settings: TextTranceSessionSettings
    let readerReferenceCharacterCount: Int

    private let light: (any LightLayerControlling)?
    private let audio: (any AudioLayerControlling)?
    private let sleep: @Sendable (Duration) async -> Void
    private let now: @Sendable () -> TimeInterval
    private var schedule: [PacedWord] = []
    private var seekRequested = false
    private var cancelled = false
    private var isRunning = false
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private let progressStore: ReaderProgressStore?
    private let scriptContentHash: String

    init(script: TranceScript,
         settings: TextTranceSessionSettings,
         light: (any LightLayerControlling)?,
         audio: (any AudioLayerControlling)?,
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         progressStore: ReaderProgressStore? = nil,
         scriptContentHash: String = "") {
        self.script = script
        self.settings = settings
        self.speedMultiplier = settings.speedMultiplier
        self.subliminalEnabled = settings.subliminalEnabled
        self.subliminalSpeed = settings.subliminalSpeed
        self.binauralActive = settings.binauralEnabled
        self.lightEnabledLive = settings.lightEnabled
        self.light = light
        self.audio = audio
        self.sleep = sleep
        self.now = now
        self.progressStore = progressStore
        self.scriptContentHash = scriptContentHash
        // Sizing depends on word lengths, not durations; build at neutral speed.
        self.readerReferenceCharacterCount = TextTranceWordSizing.referenceCharacterCount(
            for: TextPacingEngine.schedule(
                for: script,
                settings: TextPacingSettings(arc: settings.arc,
                                             speedMultiplier: 1.0,
                                             subliminalEnabled: settings.subliminalEnabled,
                                             subliminalSpeed: settings.subliminalSpeed)))
    }

    /// Base schedule at neutral speed; live speed is applied per-word at the hold site.
    private func makeSchedule() -> [PacedWord] {
        TextPacingEngine.schedule(
            for: script,
            settings: TextPacingSettings(arc: settings.arc,
                                         speedMultiplier: 1.0,
                                         subliminalEnabled: subliminalEnabled,
                                         subliminalSpeed: subliminalSpeed))
    }

    /// Live-scaled hold: readable words scale inversely with speed; flashes are fixed.
    private func scaledHold(for word: PacedWord) -> TimeInterval {
        word.isSubliminal ? word.duration : word.duration / max(speedMultiplier, 0.0001)
    }

    private func render(_ word: PacedWord) {
        currentWord = word.text
        currentPivotIndex = word.pivotIndex
        currentPhase = word.phase
        currentFade = word.fade
        currentDuration = scaledHold(for: word)
    }

    /// Run the session to completion (or until `end()` cancels it).
    func begin() async { await begin(from: 0) }

    func begin(from startIndex: Int) async {
        guard !cancelled, !isComplete, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        if binauralActive { startBinaural() }

        schedule = makeSchedule()
        currentWordIndex = min(max(startIndex, 0), schedule.count)

        isReading = true
        while currentWordIndex < schedule.count, !cancelled, !Task.isCancelled {
            let word = schedule[currentWordIndex]
            render(word)
            await holdCurrentWord(scaledHold(for: word))
            if cancelled || Task.isCancelled { break }
            if seekRequested {       // loop re-enters at the seeked index
                seekRequested = false
                continue
            }
            currentWordIndex += 1
        }
        isReading = false

        if settings.arc == .handoff, shouldRunHandoffTail, !cancelled, !Task.isCancelled {
            if lightEnabledLive, let light {
                light.start()
                lightActive = true
            }
            await sleep(.seconds(settings.postHandoffDuration))
            if lightActive {
                light?.stop()
                lightActive = false
            }
        }

        if binauralActive { audio?.stop() }
        isComplete = !cancelled && !Task.isCancelled
        if isComplete { progressStore?.clear(scriptId: script.id) }
    }

    private var shouldRunHandoffTail: Bool {
        (lightEnabledLive && light != nil) || binauralActive
    }

    /// Snapshot the current position + live settings for resume-after-close.
    private func currentSnapshot() -> ReaderResumeState {
        ReaderResumeState(
            scriptId: script.id,
            wordIndex: currentWordIndex,
            settings: PersistedReaderSettings(
                arc: settings.arc,
                speedMultiplier: speedMultiplier,
                subliminalEnabled: subliminalEnabled,
                subliminalSpeed: subliminalSpeed,
                binauralEnabled: binauralActive,
                lightEnabled: lightEnabledLive,
                beatFrequency: settings.beatFrequency),
            phase: .reading,
            scriptContentHash: scriptContentHash,
            savedAt: .now)
    }

    /// Persist the current position so the session can resume after close.
    func persistProgress() {
        guard !isComplete, isReading else { return }
        progressStore?.save(currentSnapshot())
    }

    /// Sync the configured beat and start the binaural layer.
    private func startBinaural() {
        guard let audio else { return }
        audio.syncBeatFrequency(to: settings.beatFrequency)
        audio.start()
    }

    /// Hold the current word, honoring pause. On pause mid-hold we keep the
    /// remaining time and suspend until `resume()`.
    private func holdCurrentWord(_ fullDuration: TimeInterval) async {
        var remaining = fullDuration
        while remaining > 0, !cancelled, !Task.isCancelled {
            if seekRequested { return }
            if isPaused {
                await withCheckedContinuation { resumeContinuation = $0 }
                continue
            }
            let start = now()
            let holdDuration = Duration.seconds(remaining)
            let task = Task { [sleep] in await sleep(holdDuration) }
            holdTask = task
            await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            holdTask = nil
            if cancelled || Task.isCancelled { return }
            if seekRequested { return }
            if isPaused {
                let elapsed = now() - start
                remaining = max(0, remaining - elapsed)
                continue
            }
            remaining = 0
        }
    }

    /// Pause word advance and the binaural layer.
    func pause() {
        guard isReading, !isPaused, !isComplete else { return }
        isPaused = true
        holdTask?.cancel()                 // wake the in-flight hold promptly
        if binauralActive { audio?.stop() }
        persistProgress()
    }

    /// Resume word advance and the binaural layer.
    func resume() {
        guard isPaused, !isComplete else { return }
        isPaused = false
        if binauralActive, isReading { startBinaural() }
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    /// Toggle subliminal flashing mid-session. Regenerates the base schedule
    /// (word sequence is invariant) and keeps the current index/word.
    func setSubliminal(enabled: Bool, speed: TextPacingSettings.SubliminalSpeed) {
        subliminalEnabled = enabled
        subliminalSpeed = speed
        let index = currentWordIndex
        schedule = makeSchedule()
        currentWordIndex = min(index, max(schedule.count - 1, 0))
        if currentWordIndex < schedule.count { render(schedule[currentWordIndex]) }
    }

    /// Toggle the binaural layer live. Starts only while actively reading.
    func setBinaural(enabled: Bool) {
        guard enabled != binauralActive else { return }
        binauralActive = enabled
        if enabled {
            if isReading, !isPaused { startBinaural() }
        } else {
            audio?.stop()
        }
    }

    /// Toggle the post-handoff light tail (applied when the tail begins).
    func setLightEnabled(_ enabled: Bool) {
        lightEnabledLive = enabled
    }

    /// Clamp + apply a live speed multiplier and re-render the current word.
    func setSpeed(multiplier: Double) {
        speedMultiplier = min(max(multiplier, TextPacingEngine.minSpeedMultiplier),
                              TextPacingEngine.maxSpeedMultiplier)
        if currentWordIndex < schedule.count { render(schedule[currentWordIndex]) }
    }

    /// Stop everything immediately (user tap-and-hold to end).
    func end() {
        guard !isComplete else { return }
        if isReading, !isComplete { progressStore?.save(currentSnapshot()) }
        cancelled = true
        holdTask?.cancel()
        if isPaused {
            isPaused = false
            resumeContinuation?.resume()
            resumeContinuation = nil
        }
        if lightActive {
            light?.stop()
            lightActive = false
        }
        if binauralActive { audio?.stop() }
        isReading = false
    }
}
