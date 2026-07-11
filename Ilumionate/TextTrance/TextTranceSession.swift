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
    let attentionGateEnabled: Bool
    let narrationEnabled: Bool
    let speedTraining: ReaderSpeedTrainingSettings
    let displayPreferences: ReaderDisplayPreferences

    init(arc: ScriptArc,
         speedMultiplier: Double,
         lightEnabled: Bool,
         binauralEnabled: Bool,
         beatFrequency: Double,
         postHandoffDuration: TimeInterval,
         subliminalEnabled: Bool = true,
         subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium,
         attentionGateEnabled: Bool = false,
         narrationEnabled: Bool = false,
         speedTraining: ReaderSpeedTrainingSettings = .standard,
         displayPreferences: ReaderDisplayPreferences = .standard) {
        self.arc = arc
        self.speedMultiplier = speedMultiplier
        self.lightEnabled = lightEnabled
        self.binauralEnabled = binauralEnabled
        self.beatFrequency = beatFrequency
        self.postHandoffDuration = postHandoffDuration
        self.subliminalEnabled = subliminalEnabled
        self.subliminalSpeed = subliminalSpeed
        self.attentionGateEnabled = attentionGateEnabled
        self.narrationEnabled = narrationEnabled
        self.speedTraining = speedTraining
        self.displayPreferences = displayPreferences
    }

    /// Convenience for the legacy three presets (tests, anchors).
    init(arc: ScriptArc,
         speed: TextPacingSettings.Speed,
         lightEnabled: Bool,
         binauralEnabled: Bool,
         beatFrequency: Double,
         postHandoffDuration: TimeInterval,
         subliminalEnabled: Bool = true,
         subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium,
         attentionGateEnabled: Bool = false,
         narrationEnabled: Bool = false,
         speedTraining: ReaderSpeedTrainingSettings = .standard,
         displayPreferences: ReaderDisplayPreferences = .standard) {
        self.init(arc: arc, speedMultiplier: speed.multiplier,
                  lightEnabled: lightEnabled, binauralEnabled: binauralEnabled,
                  beatFrequency: beatFrequency, postHandoffDuration: postHandoffDuration,
                  subliminalEnabled: subliminalEnabled, subliminalSpeed: subliminalSpeed,
                  attentionGateEnabled: attentionGateEnabled,
                  narrationEnabled: narrationEnabled,
                  speedTraining: speedTraining,
                  displayPreferences: displayPreferences)
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
    private(set) var sections: [ReaderSection] = []

    // Control state
    private(set) var currentWordIndex = 0
    private(set) var isPaused = false
    var speedMultiplier: Double
    private(set) var attentionGateEnabled: Bool
    private(set) var attentionSatisfied = true
    private(set) var isAttentionPaused = false

    /// Reading progress by word position, 0…1. Drives the reader's progress line.
    var progressFraction: Double {
        schedule.isEmpty ? 0 : min(1, Double(currentWordIndex) / Double(schedule.count))
    }

    /// Total scheduled words (0 before `begin()` builds the schedule).
    var wordCount: Int { schedule.count }

    var currentSection: ReaderSection? {
        sections.last { $0.wordIndex <= currentWordIndex }
    }

    /// Phase of the scheduled word at `index`; nil out of range or pre-begin.
    func phase(atWordIndex index: Int) -> TrancePhase? {
        schedule.indices.contains(index) ? schedule[index].phase : nil
    }

    /// Reposition the word cursor (scrubbing). Renders the target word
    /// immediately; the playback loop continues from the new index. Pause
    /// state is left untouched — a paused session stays paused.
    func seek(toWordIndex index: Int, savingProgress: Bool = false) {
        guard isReading, !isComplete, !cancelled, !schedule.isEmpty else { return }
        currentWordIndex = min(max(index, 0), schedule.count - 1)
        render(schedule[currentWordIndex])
        seekRequested = true
        holdTask?.cancel()          // break any in-flight hold promptly
        if savingProgress {
            persistProgress()
            restartNarrationAfterCommittedSeek()
        }
    }

    // Live, mutable copies of schedule-affecting settings.
    private(set) var subliminalEnabled: Bool
    private(set) var subliminalSpeed: TextPacingSettings.SubliminalSpeed
    private(set) var binauralActive: Bool
    private(set) var lightEnabledLive: Bool
    private(set) var narrationActive: Bool
    private(set) var speedTraining: ReaderSpeedTrainingSettings
    private(set) var displayPreferences: ReaderDisplayPreferences

    let script: TranceScript
    let settings: TextTranceSessionSettings
    let readerReferenceCharacterCount: Int

    private let light: (any LightLayerControlling)?
    private let audio: (any AudioLayerControlling)?
    private let narration: (any NarrationControlling)?
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
         narration: (any NarrationControlling)? = nil,
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         progressStore: ReaderProgressStore? = nil,
         scriptContentHash: String = "") {
        self.script = script
        self.settings = settings
        self.speedMultiplier = settings.speedMultiplier
        self.subliminalEnabled = settings.subliminalEnabled
        self.subliminalSpeed = settings.subliminalSpeed
        self.attentionGateEnabled = settings.attentionGateEnabled
        self.binauralActive = settings.binauralEnabled
        self.lightEnabledLive = settings.lightEnabled
        self.narrationActive = settings.narrationEnabled
        self.speedTraining = settings.speedTraining
        self.displayPreferences = settings.displayPreferences
        self.light = light
        self.audio = audio
        self.narration = narration
        self.sleep = sleep
        self.now = now
        self.progressStore = progressStore
        self.scriptContentHash = scriptContentHash
        // Sizing depends on word lengths and chunks, not durations.
        self.readerReferenceCharacterCount = TextTranceWordSizing.referenceCharacterCount(
            for: TextPacingEngine.schedule(
                for: script,
                settings: TextPacingSettings(arc: settings.arc,
                                             speedMultiplier: settings.speedMultiplier,
                                             subliminalEnabled: settings.subliminalEnabled,
                                             subliminalSpeed: settings.subliminalSpeed,
                                             speedTraining: settings.speedTraining)))
    }

    /// Current schedule. Speed-training changes rebuild this schedule.
    private func makeSchedule() -> [PacedWord] {
        TextPacingEngine.schedule(
            for: script,
            settings: TextPacingSettings(arc: settings.arc,
                                         speedMultiplier: speedMultiplier,
                                         subliminalEnabled: subliminalEnabled,
                                         subliminalSpeed: subliminalSpeed,
                                         speedTraining: speedTraining))
    }

    /// The schedule already includes speed, chunking, and punctuation timing.
    private func scaledHold(for word: PacedWord) -> TimeInterval {
        word.duration
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
        sections = ReaderSectionIndex.sections(for: script, arc: settings.arc)
        currentWordIndex = min(max(startIndex, 0), schedule.count)

        isReading = true
        startNarration(at: currentWordIndex)
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
        narration?.stop()
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
                beatFrequency: settings.beatFrequency,
                attentionGateEnabled: attentionGateEnabled,
                narrationEnabled: narrationActive,
                speedTraining: speedTraining,
                displayPreferences: displayPreferences),
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
                await waitForResume()
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
                await waitForResume()
                if cancelled || Task.isCancelled { return }
                if seekRequested { return }
                continue
            }
            remaining = 0
        }
    }

    private func waitForResume() async {
        await withCheckedContinuation { resumeContinuation = $0 }
    }

    /// Pause word advance and the binaural layer.
    func pause() {
        guard isReading, !isPaused, !isComplete else { return }
        isPaused = true
        holdTask?.cancel()                 // wake the in-flight hold promptly
        if binauralActive { audio?.stop() }
        if narrationActive { narration?.pause() }
        persistProgress()
    }

    /// Resume word advance and the binaural layer.
    func resume() {
        guard isPaused, !isComplete, !isAttentionPaused else { return }
        guard !attentionGateEnabled || attentionSatisfied else { return }
        isPaused = false
        if binauralActive, isReading { startBinaural() }
        if narrationActive { narration?.resume() }
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    /// Toggle subliminal flashing mid-session. Regenerates the base schedule
    /// (word sequence is invariant) and keeps the current index/word.
    func setSubliminal(enabled: Bool, speed: TextPacingSettings.SubliminalSpeed) {
        subliminalEnabled = enabled
        subliminalSpeed = speed
        rebuildScheduleKeepingCurrentIndex()
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

    /// Toggle spoken narration live. Narration starts from the current word.
    func setNarration(enabled: Bool) {
        guard enabled != narrationActive else { return }
        narrationActive = enabled
        if enabled {
            if isReading {
                startNarration(at: currentWordIndex)
                if isPaused { narration?.pause() }
            }
        } else {
            narration?.stop()
        }
    }

    /// Toggle the post-handoff light tail (applied when the tail begins).
    func setLightEnabled(_ enabled: Bool) {
        lightEnabledLive = enabled
    }

    /// Enables the gaze/attention gate. The view owns camera monitoring and
    /// feeds its current observation through `setReaderAttention`.
    func setAttentionGate(enabled: Bool) {
        guard attentionGateEnabled != enabled else { return }
        attentionGateEnabled = enabled
        if !enabled {
            attentionSatisfied = true
            if isAttentionPaused {
                isAttentionPaused = false
                resume()
            }
        }
    }

    /// Auto-pause while attention is absent and auto-resume only if the
    /// session was paused by this gate, preserving manual pause semantics.
    func setReaderAttention(isLookingAtScreen: Bool) {
        attentionSatisfied = isLookingAtScreen
        guard attentionGateEnabled, isReading, !isComplete, !cancelled else { return }

        if isLookingAtScreen {
            guard isAttentionPaused else { return }
            isAttentionPaused = false
            resume()
        } else {
            guard !isPaused else { return }
            isAttentionPaused = true
            pause()
        }
    }

    /// Clamp + apply a live speed multiplier and re-render the current word.
    func setSpeed(multiplier: Double) {
        speedMultiplier = min(max(multiplier, TextPacingEngine.minSpeedMultiplier),
                              TextPacingEngine.maxSpeedMultiplier)
        speedTraining.targetWPM = TextPacingEngine.nominalWPM(forMultiplier: speedMultiplier)
        rebuildScheduleKeepingCurrentIndex()
    }

    /// Replace the full speed-training profile and rebuild the timed schedule.
    func setSpeedTraining(_ settings: ReaderSpeedTrainingSettings) {
        speedTraining = settings
        speedMultiplier = settings.targetSpeedMultiplier
        rebuildScheduleKeepingCurrentIndex()
    }

    /// Replace display preferences. The player view reacts immediately.
    func setDisplayPreferences(_ preferences: ReaderDisplayPreferences) {
        displayPreferences = preferences
    }

    private func rebuildScheduleKeepingCurrentIndex() {
        guard isReading || !schedule.isEmpty else { return }
        let readableAnchor = readableAnchor(for: currentWordIndex, in: schedule)
        let fallbackProgress = progressFraction
        schedule = makeSchedule()
        currentWordIndex = index(forReadableAnchor: readableAnchor,
                                 fallbackProgress: fallbackProgress,
                                 in: schedule)
        if currentWordIndex < schedule.count {
            render(schedule[currentWordIndex])
            seekRequested = true
            holdTask?.cancel()
            restartNarrationAfterCommittedSeek()
        }
    }

    private func readableAnchor(for index: Int, in schedule: [PacedWord]) -> Int? {
        guard schedule.indices.contains(index) else { return nil }
        if let anchor = schedule[index].readableStartIndex { return anchor }

        if index > schedule.startIndex {
            let previousRange = schedule[..<index]
            if let previous = previousRange.last(where: { $0.readableStartIndex != nil }),
               let start = previous.readableStartIndex {
                return start + max(previous.readableWordCount - 1, 0)
            }
        }

        if let next = schedule[index...].first(where: { $0.readableStartIndex != nil }) {
            return next.readableStartIndex
        }

        return nil
    }

    private func index(forReadableAnchor anchor: Int?,
                       fallbackProgress: Double,
                       in schedule: [PacedWord]) -> Int {
        guard !schedule.isEmpty else { return 0 }
        if let anchor {
            for index in schedule.indices {
                guard let start = schedule[index].readableStartIndex else { continue }
                let end = start + max(schedule[index].readableWordCount - 1, 0)
                if anchor <= end { return index }
            }
            return schedule.count - 1
        }

        let fallbackIndex = Int((fallbackProgress * Double(schedule.count - 1)).rounded())
        return min(max(fallbackIndex, 0), schedule.count - 1)
    }

    /// Stop everything immediately (user tap-and-hold to end).
    func end() {
        guard !isComplete, !cancelled else { return }
        if isReading, !isComplete { progressStore?.save(currentSnapshot()) }
        cancelled = true
        isAttentionPaused = false
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
        narration?.stop()
        isReading = false
    }

    private func startNarration(at index: Int) {
        guard narrationActive, let narration else { return }
        let text = narrationText(from: index)
        narration.start(text: text, speedMultiplier: speedMultiplier)
    }

    private func restartNarrationAfterCommittedSeek() {
        guard narrationActive, isReading else { return }
        startNarration(at: currentWordIndex)
        if isPaused { narration?.pause() }
    }

    private func narrationText(from index: Int) -> String {
        guard index < schedule.count else { return "" }
        return schedule[index...]
            .filter { !$0.isSubliminal }
            .map(\.text)
            .joined(separator: " ")
    }
}
