//
//  UnifiedPlayerViewModel.swift
//  Ilumionate
//
//  Central view model coordinating all player modes through existing controllers.
//

import SwiftUI
import os
import AVFoundation

// MARK: - Playback State

nonisolated enum PlaybackState: Equatable, Sendable {
    case idle
    case countdown
    case playing
    case paused
    case complete
}

// MARK: - Unified Player View Model

@MainActor
@Observable
final class UnifiedPlayerViewModel {

    // MARK: - Inputs

    let mode: PlayerMode
    let engine: LightEngine

    // MARK: - Injected Dependencies
    // Default to the shared singletons in production; injectable for testing.
    private let nowPlaying: NowPlayingState
    private let analysisManager: AnalysisStateManager
    private let sessionHistory: SessionHistoryManager
    private let haptics: TranceHaptics
    private let mindMachineEntryPoint: MindMachineEntryPoint?
    private let configuredMindMachineMode: MindMachineMode?
    private let playbackProgressStore: PlaybackProgressStore
    private let savedSessionStore: SavedSessionStore

    // MARK: - Universal Playback State

    private(set) var playbackState: PlaybackState = .idle
    private(set) var countdownValue: Int? = nil
    private(set) var countdownMessage: String? = nil
    /// True when this session opened with the VoiceOver numeral fallback
    /// rather than the threshold. Held explicitly rather than inferred from
    /// `countdownValue`, which also goes nil mid-flow when the held line
    /// replaces the count.
    private(set) var usesNumericCountdown = false
    /// Drives the threshold arc. Nil on the numeric path.
    private(set) var thresholdController: ThresholdController?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var lightOutputMultiplier: Double = 1
    private(set) var didReachLightExposureLimit = false
    var showingControls = true
    var showingSafetyWarning = false
    var showingLightSyncWarning = false
    private(set) var interruptionNotice: String?
    private(set) var isCurrentSessionSaved = false
    private(set) var recommendedNextMode: PlayerMode?

    // MARK: - Countdown Setting

    @ObservationIgnored
    private var countdownDuration: Int {
        userDefaults.integer(forKey: "countdownDuration").clamped(options: [3, 7, 10])
    }

    // MARK: - Session Mode State

    private var lightScorePlayer: LightScorePlayer?
    private var audioSync: AudioSyncController?
    private var playbackRuntime: (any PlaybackRuntime)?
    private var lightExposureBudget = LightExposureBudget(limit: .recommended)
    var currentPhase = "Induction Phase"

    // MARK: - Flash Mode State

    private(set) var flashController: FlashController?
    var bilateralMode = false {
        didSet { flashController?.bilateralMode = bilateralMode }
    }
    var bilateralDriftRate: Double = 0.05 {
        didSet { flashController?.bilateralDriftRate = bilateralDriftRate }
    }
    var bilateralDriftProgress: Double { flashController?.bilateralDriftProgress ?? 0.0 }
    var flashFrequency: Double = LightSafety.maxFlashHz
    var flashColorTemperature: Int = 3000

    // MARK: - Visual Field State

    /// Live copy of the field's settings, so strength and speed can be tuned
    /// mid-session without ending it — the same affordance the reader's tray has.
    var visualFieldSettings: VisualFieldSettings = .standard
    /// Rides the field's strength down over the last seconds of a timed session.
    private(set) var visualFieldFade: Double = 1
    /// Set when a Visual Field session's accompanying track could not play.
    ///
    /// The session keeps running regardless — see VisualFieldAudioFailure. This
    /// only disables the volume tile and lets the view say so.
    private(set) var audioUnavailable = false

    // MARK: - Binaural State

    private var binauralEngine: BinauralBeatsEngine?
    var binauralActive = false {
        didSet { updateBinauralState() }
    }

    // MARK: - Audio Mode State

    private var audioLightSyncPlayer: AudioLightSyncPlayer?
    var lightSyncEnabled = false
    private(set) var lightSession: LightSession?
    var volume: Float = 0.7

    // MARK: - Playlist State

    private(set) var playlistController: PlaylistPlayerController?
    var showingTrackList = false

    // MARK: - Persistence

    @ObservationIgnored
    private var lastSessionId: String {
        get { userDefaults.string(forKey: "lastSessionId") ?? "" }
        set { userDefaults.set(newValue, forKey: "lastSessionId") }
    }

    @ObservationIgnored
    private var lastSessionProgress: Double {
        get { userDefaults.double(forKey: "lastSessionProgress") }
        set { userDefaults.set(newValue, forKey: "lastSessionProgress") }
    }

    // MARK: - Safety Warnings

    @ObservationIgnored
    private var hasSeenFlashWarning: Bool {
        get { userDefaults.bool(forKey: "hasSeenFlashWarning") }
        set { userDefaults.set(newValue, forKey: "hasSeenFlashWarning") }
    }

    @ObservationIgnored
    private var hasSeenLightSyncWarning: Bool {
        get { userDefaults.bool(forKey: "hasSeenLightSyncWarning") }
        set { userDefaults.set(newValue, forKey: "hasSeenLightSyncWarning") }
    }

    // MARK: - Private

    private var uiUpdateTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var savedBrightness: CGFloat = 1.0
    /// Guards `savedBrightness` so the player's own forced 1.0 can never be
    /// captured as the user's preferred level.
    private var hasCapturedBrightness = false
    private var hasStarted = false
    private var analyticsLifecycle = PlaybackAnalyticsLifecycle()
    private var playbackStartType: PlaybackStartType = .fresh
    private var hasRecordedHistoryForAttempt = false
    private var hasReportedCreateOutcome = false
    private var didPrepareRecommendation = false
    private var lastPersistedProgressSecond = -1
    @ObservationIgnored private let userDefaults: UserDefaults

    /// When true, `onDisappear` will not stop playback — used for mini-player dismiss.
    var dismissToMiniPlayer = false

    // MARK: - Init

    init(
        mode: PlayerMode,
        engine: LightEngine,
        initialLightSession: LightSession? = nil,
        nowPlaying: NowPlayingState? = nil,
        analysisManager: AnalysisStateManager? = nil,
        sessionHistory: SessionHistoryManager? = nil,
        haptics: TranceHaptics? = nil,
        mindMachineEntryPoint: MindMachineEntryPoint? = nil,
        mindMachineMode: MindMachineMode? = nil,
        playbackProgressStore: PlaybackProgressStore? = nil,
        savedSessionStore: SavedSessionStore? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.mode = mode
        self.engine = engine
        self.nowPlaying = nowPlaying ?? .shared
        self.analysisManager = analysisManager ?? .shared
        self.sessionHistory = sessionHistory ?? .shared
        self.haptics = haptics ?? .shared
        self.mindMachineEntryPoint = mindMachineEntryPoint
        self.configuredMindMachineMode = mindMachineMode
        self.playbackProgressStore = playbackProgressStore ?? .shared
        self.savedSessionStore = savedSessionStore ?? .shared
        self.userDefaults = userDefaults
        self.lightSession = initialLightSession
        self.lightExposureBudget = LightExposureBudget(
            limit: AppSettingsManager.maximumLightTime(defaults: userDefaults)
        )

        if case .flashMode(let freq, _, let colorTemp, _, _, _, _, _) = mode {
            flashFrequency = LightSafety.clampFlashHz(freq)
            flashColorTemperature = colorTemp
            bilateralMode = mindMachineMode == .bilateral
        }

        if case .visualField(let settings, _, _) = mode {
            visualFieldSettings = settings
        }

        showingSafetyWarning = mode.requiresSafetyWarning && !hasSeenFlashWarning
        isCurrentSessionSaved = Self.isSaved(mode: mode, savedSessionStore: self.savedSessionStore)
    }

    // MARK: - Lifecycle

    func onAppear() {
        let isFreshPresentation = playbackState == .idle && currentTime == 0
        dismissToMiniPlayer = false
        captureScreenBrightnessIfNeeded()
        applyStoredMindMachinePreference()
        PlatformApplication.keepsScreenAwake = AppSettingsManager.keepsScreenAwakeDuringSessions()
        if !hasStarted {
            setupMode()
        }
        applyMindMachineScreenPolicy()
        prepareRecommendedNextModeIfNeeded()
        startUIUpdateTimer()
        nowPlaying.activate(
            mode: mode,
            title: mode.title,
            engine: engine,
            viewModel: self,
            resetProgress: isFreshPresentation
        )

        // The visual field starts itself: its shader background renders
        // whenever it is on screen, so an idle player in front of a moving
        // field reads as a broken paused state. Other modes keep the explicit
        // play tap. Fresh presentations only — returning from the mini-player
        // must not restart a session.
        if isFreshPresentation, mode.beginsAutomatically, !showingSafetyWarning {
            startCountdownAndPlay()
        }
    }

    /// Records the user's own screen brightness exactly once per presentation,
    /// before the player forces it to 1.0.
    private func captureScreenBrightnessIfNeeded() {
        guard !hasCapturedBrightness else { return }
        savedBrightness = PlatformApplication.screenBrightness
        hasCapturedBrightness = true
    }

    func onDisappear() {
        stopUIUpdateTimer()
        PlatformApplication.keepsScreenAwake = false
        if dismissToMiniPlayer {
            // Keep this exact player alive so the mini-player can resume it.
            nowPlaying.updatePlaybackState(playbackState)
        } else {
            reportPlayerLifecycle(.dismissed)
            stopAll(reason: .dismissed)
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        haptics.medium()

        switch playbackState {
        case .idle:
            startCountdownAndPlay()
        case .playing:
            pause()
        case .paused:
            resume()
        case .countdown:
            break // ignore during countdown
        case .complete:
            replayCompletedSession()
        }
    }

    /// Pause safely when the system interrupts the app (for example, a phone
    /// call). Playback never resumes automatically after an interruption.
    func handleAudioSessionInterruption(_ notification: Notification) {
        guard PlatformAudioSession.interruptionBegan(notification) else { return }

        handlePlaybackInterruption()
    }

    /// Persist the latest position before suspension. Background-capable audio
    /// may keep playing; this snapshot protects against process termination.
    func persistProgressForBackground() {
        persistPlaybackProgress()
        guard playbackState == .countdown else { return }
        cancelPendingStart(message: "Start cancelled while the app was inactive")
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            reportPlayerLifecycle(.foregrounded)
        case .background:
            persistProgressForBackground()
            reportPlayerLifecycle(.backgrounded)
        case .inactive:
            persistProgressForBackground()
        @unknown default:
            persistProgressForBackground()
        }
    }

    func dismissInterruptionNotice() {
        interruptionNotice = nil
    }

    func finishCompletedSession() {
        guard playbackState == .complete else { return }
        UsageAnalytics.shared.sessionCompletionAction(
            .done,
            source: sessionSource,
            category: sessionCategory
        )
        stopAll(reason: .completed)
    }

    func replayCompletedSession() {
        guard playbackState == .complete else { return }
        UsageAnalytics.shared.sessionCompletionAction(
            .replay,
            source: sessionSource,
            category: sessionCategory
        )
        playbackStartType = .fresh
        seek(to: 0)
        currentTime = 0
        startCountdownAndPlay()
    }

    func saveCompletedSession() {
        guard playbackState == .complete else { return }
        switch mode {
        case .session(let session, let audioFile):
            if let audioFile {
                Task { await AudioLibraryStore.setFavorite(true, audioFileID: audioFile.id) }
            } else {
                savedSessionStore.save(session.id.uuidString)
            }
        case .audioLight(let audioFile):
            Task { await AudioLibraryStore.setFavorite(true, audioFileID: audioFile.id) }
        case .flashMode, .colorPulse, .playlist, .visualField:
            return
        }
        isCurrentSessionSaved = true
        UsageAnalytics.shared.sessionCompletionAction(
            .save,
            source: sessionSource,
            category: sessionCategory
        )
    }

    var canSaveCompletedSession: Bool {
        switch mode {
        case .session, .audioLight: true
        case .flashMode, .colorPulse, .playlist, .visualField: false
        }
    }

    func recordNextSessionSelection() {
        UsageAnalytics.shared.sessionCompletionAction(
            .next,
            source: sessionSource,
            category: sessionCategory
        )
    }

    func seek(to time: TimeInterval) {
        PerformanceTrace.event("Playback Seek")
        playbackRuntime?.seek(to: time)
        currentTime = playbackRuntime?.snapshot(elapsed: 0).currentTime ?? time
    }

    func seekByProgress(_ progress: Double) {
        seek(to: duration * progress)
    }

    func skipForward15() {
        seek(to: min(duration, currentTime + 15))
    }

    func skipBack15() {
        seek(to: max(0, currentTime - 15))
    }

    func skipNext() async {
        await playlistController?.skipNext()
    }

    func skipPrevious() async {
        await playlistController?.skipPrevious()
    }

    func jumpToTrack(at index: Int) async {
        await playlistController?.jumpToItem(at: index)
    }

    // MARK: - Volume

    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        playbackRuntime?.setVolume(volume)
    }

    // MARK: - Light Sync (Audio Mode)

    func toggleLightSync() {
        guard didReachLightExposureLimit == false else { return }
        haptics.medium()

        switch lightSyncStatus {
        case .enabled:
            PerformanceTrace.event("Light Sync Disable")
            withAnimation(.easeInOut(duration: 0.4)) { lightSyncEnabled = false }
            audioLightSyncPlayer?.disableLightSync()
        case .ready:
            PerformanceTrace.event("Light Sync Enable Requested")
            guard let session = lightSession else { return }
            if hasSeenLightSyncWarning {
                enableLightSync(session: session)
            } else {
                showingLightSyncWarning = true
            }
        case .analyzing:
            break
        case .queued(let position):
            if position > 1, case .audioLight(let file) = mode {
                analysisManager.prioritizeInQueue(audioFile: file)
            }
        case .unavailable:
            if case .audioLight(let file) = mode {
                Task { await analysisManager.queueForAnalysis(file) }
            }
        }
    }

    func enableLightSync(session: LightSession) {
        guard didReachLightExposureLimit == false else { return }
        hasSeenLightSyncWarning = true
        withAnimation(.easeInOut(duration: 0.4)) { lightSyncEnabled = true }
        audioLightSyncPlayer?.enableLightSync(lightSession: session)
    }

    func acknowledgeLightSyncWarning() {
        if let lightSession {
            enableLightSync(session: lightSession)
        }
        showingLightSyncWarning = false
    }

    var lightSyncStatus: LightSyncStatus {
        if lightSyncEnabled { return .enabled }
        if lightSession != nil { return .ready }

        guard case .audioLight(let file) = mode else { return .unavailable }

        let manager = analysisManager
        if let current = manager.currentAnalysis,
           current.audioFile.id == file.id {
            return .analyzing(progress: current.progress, stage: stageLabel(current.stage))
        }
        let pos = manager.queuePosition(for: file)
        if pos > 0 { return .queued(position: pos) }
        return .unavailable
    }

    // MARK: - Mind Machine Gate (Session / Playlist)

    /// Whether light output is running. Turning this off drops to audio-only:
    /// the engine stops driving output, the screen returns to the user's own
    /// brightness, and the device is allowed to sleep.
    var mindMachineEnabled: Bool {
        get { engine.mindMachineEnabled }
        set {
            guard newValue != engine.mindMachineEnabled else { return }
            engine.mindMachineEnabled = newValue
            if mode.hasMindMachineToggle {
                userDefaults.set(newValue, forKey: AppSettingsManager.Key.mindMachineEnabled)
            }
            applyMindMachineScreenPolicy()
        }
    }

    func toggleMindMachine() {
        guard didReachLightExposureLimit == false else { return }
        haptics.medium()
        mindMachineEnabled.toggle()
    }

    /// Lights on: hold the screen bright and awake for entrainment.
    /// Lights off: hand the screen back so the phone can go in a pocket.
    private func applyMindMachineScreenPolicy() {
        guard mode.hasMindMachineToggle else { return }
        if engine.mindMachineEnabled {
            if playbackState == .playing || playbackState == .countdown {
                PlatformApplication.screenBrightness = 1.0
            }
            PlatformApplication.keepsScreenAwake =
                AppSettingsManager.keepsScreenAwakeDuringSessions(defaults: userDefaults)
        } else {
            PlatformApplication.screenBrightness = savedBrightness
            PlatformApplication.keepsScreenAwake = false
        }
    }

    /// Apply the stored preference for modes that own it. Modes that do not
    /// (notably `.audioLight`, which has its own Light Sync control) must get
    /// an ungated engine so their own toggle still works.
    private func applyStoredMindMachinePreference() {
        guard didReachLightExposureLimit == false else {
            engine.mindMachineEnabled = false
            return
        }
        engine.mindMachineEnabled = mode.hasMindMachineToggle
            ? AppSettingsManager.isMindMachineEnabled(defaults: userDefaults)
            : true
    }

    // MARK: - Bilateral / Binaural (Flash Mode)

    func toggleBilateral() {
        bilateralMode.toggle()
        haptics.medium()
    }

    func toggleBinaural() {
        binauralActive.toggle()
        haptics.medium()
    }

    func setDriftRate(_ rate: Double) {
        bilateralDriftRate = rate
        haptics.light()
    }

    // MARK: - Safety Warning

    func acknowledgeSafetyWarning() {
        hasSeenFlashWarning = true
        showingSafetyWarning = false
    }

    // MARK: - Playlist Accessors

    var smartTransitions: Bool {
        get { playlistController?.smartTransitions ?? true }
        set { playlistController?.smartTransitions = newValue }
    }

    var currentTrackIndex: Int { playlistController?.currentItemIndex ?? 0 }
    var trackCount: Int { playlistController?.itemCount ?? 0 }
    var currentTrackName: String { playlistController?.currentItem?.filename ?? "" }
    var currentTrackDuration: TimeInterval { playlistController?.currentItemDuration ?? 0 }
    var isFirstTrack: Bool { playlistController?.isFirstItem ?? true }
    var isLastTrack: Bool { playlistController?.isLastItem ?? true }

    var playlistItems: [PlaylistItem] {
        if case .playlist(let playlist) = mode {
            return playlist.items
        }
        return []
    }

    // MARK: - Computed

    var volumeDouble: Double {
        get { Double(volume) }
        set { setVolume(Float(newValue)) }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var isPlaying: Bool { playbackState == .playing }

    var lightExposureLimit: LightExposureLimit {
        lightExposureBudget.limit
    }

    var lightExposureRemaining: TimeInterval {
        switch mode {
        case .flashMode, .colorPulse:
            return max(0, duration - currentTime)
        case .session, .audioLight:
            guard duration > 0 else { return lightExposureBudget.remaining }
            return min(lightExposureBudget.remaining, max(0, duration - currentTime))
        case .playlist:
            return lightExposureBudget.remaining
        case .visualField:
            return 0
        }
    }

    var showsLightExposureStatus: Bool {
        switch mode {
        case .session, .flashMode, .colorPulse, .audioLight, .playlist:
            true
        case .visualField:
            false
        }
    }

    var lightExposureStatusText: String {
        if didReachLightExposureLimit {
            return hasContinuingAudioAfterLightLimit
                ? "Light limit reached · audio continuing"
                : "Light limit reached"
        }

        let remaining = Duration.seconds(lightExposureRemaining.rounded(.up))
            .formatted(.time(pattern: .minuteSecond))
        return "Lights · \(remaining) remaining"
    }

    private var hasContinuingAudioAfterLightLimit: Bool {
        switch mode {
        case .session(_, let audioFile):
            audioFile != nil
        case .audioLight, .playlist:
            true
        case .flashMode, .colorPulse, .visualField:
            false
        }
    }

    /// Flash mode left/right opacity (used by background)
    var leftOpacity: Double { flashController?.leftOpacity ?? 0 }
    var rightOpacity: Double { flashController?.rightOpacity ?? 0 }

    /// Whether the chrome should use light or dark text
    var useDarkChrome: Bool {
        switch mode {
        case .flashMode, .colorPulse, .playlist, .session, .visualField:
            return true
        case .audioLight:
            return lightSyncEnabled
        }
    }

    var labelColor: Color { useDarkChrome ? .white : .textPrimary }
    var secondaryLabelColor: Color { useDarkChrome ? .white.opacity(0.7) : .textSecondary }
    var accentColor: Color { useDarkChrome ? .white : .roseGold }

    // MARK: - Private: Setup

    private func setupMode() {
        guard !hasStarted else { return }
        let trace = PerformanceTrace.begin("Player Setup")
        defer { PerformanceTrace.end(trace) }

        switch mode {
        case .session(let session, let audioFile):
            setupSessionMode(session: session, audioFile: audioFile)

        case .flashMode(let frequency, let intensity, _, let pattern, let binauralEnabled, let binauralCarrier, let binauralVolume, let goalDuration):
            setupFlashMode(frequency: frequency, intensity: intensity, pattern: pattern,
                          binauralEnabled: binauralEnabled, binauralCarrier: binauralCarrier, binauralVolume: binauralVolume)
            duration = min(
                goalDuration ?? lightExposureBudget.limit.duration,
                lightExposureBudget.limit.duration
            )
            if let flashController {
                playbackRuntime = FlashPlaybackRuntime(
                    controller: flashController,
                    binaural: binauralEngine,
                    duration: duration,
                    volume: volume,
                    isBinauralActive: { [weak self] in self?.binauralActive == true }
                )
            }

        case .colorPulse:
            // No controller needed — TimelineView handles rendering
            duration = lightExposureBudget.limit.duration
            playbackRuntime = ManualPlaybackRuntime(duration: duration, volume: volume)

        case .visualField(let settings, let audioFile, let binaural):
            // No light controller at all: the field is a shader driven by
            // TimelineView, and it never touches LightEngine or FlashController.
            duration = settings.duration ?? 0
            if let binaural {
                setupBinaural(
                    enabled: binaural.enabled,
                    carrier: binaural.carrier,
                    volume: binaural.volume,
                    beatFrequency: binaural.beatFrequency
                )
            }
            let audioPlayer = audioFile.map(setupVisualFieldAudio)
            playbackRuntime = VisualFieldPlaybackRuntime(
                duration: duration,
                volume: volume,
                audio: audioPlayer,
                binaural: binauralEngine,
                isBinauralActive: { [weak self] in self?.binauralActive == true }
            )

        case .audioLight(let audioFile):
            setupAudioMode(audioFile: audioFile)

        case .playlist(let playlist):
            setupPlaylistMode(playlist: playlist)
        }
        hasStarted = true
    }

    private func setupSessionMode(session: LightSession, audioFile: AudioFile?) {
        let player = LightScorePlayer(session: session)
        lightScorePlayer = player
        duration = audioFile == nil
            ? min(session.duration_sec, lightExposureBudget.limit.duration)
            : session.duration_sec

        engine.attachSession(player: player)
        if !engine.isRunning { engine.start() }
        engine.pause()
        let resumeDecision = PlaybackResumeDecision(
            sessionID: session.id.uuidString,
            duration: duration,
            storedSessionID: storedResumeID(for: session.id.uuidString),
            storedProgress: storedResumeProgress(for: session.id.uuidString)
        )
        playbackStartType = resumeDecision.startType
        currentTime = resumeDecision.startTime
        player.seek(to: resumeDecision.startTime)

        // Set up binaural beats if the session defines them
        if session.binaural_enabled {
            let binaural = BinauralBeatsEngine()
            binaural.carrierFrequency = session.binaural_carrier
            binaural.volume = session.binaural_volume
            // Initial beat frequency from the first light moment
            binaural.beatFrequency = session.light_score.first?.frequency ?? 10.0
            binauralEngine = binaural
            binauralActive = true
        }

        if let audioFile {
            let sync = AudioSyncController()
            sync.audioVolume = volume
            audioSync = sync
            Task {
                do {
                    try await sync.loadAudioAsync(from: audioFile.url)
                } catch {
                    Log.general.info("Failed to load session audio: \(error)")
                }
            }
        }

        playbackRuntime = SessionPlaybackRuntime(
            scorePlayer: player,
            engine: engine,
            audio: audioSync,
            binaural: binauralEngine,
            duration: duration,
            volume: volume,
            isBinauralActive: { [weak self] in self?.binauralActive == true }
        )
    }

    private func setupFlashMode(frequency: Double, intensity: Double, pattern: MindMachineModel.LightPattern,
                                binauralEnabled: Bool, binauralCarrier: Double, binauralVolume: Double) {
        let controller = FlashController(frequency: frequency, intensity: intensity, pattern: pattern)
        flashController = controller
        duration = 0 // infinite

        setupBinaural(
            enabled: binauralEnabled,
            carrier: binauralCarrier,
            volume: binauralVolume,
            // Flash entrains with light, so the beat agrees with the light.
            beatFrequency: frequency
        )
    }

    /// Builds the binaural engine for whichever mode wants one.
    ///
    /// Shared by flash and the visual field. They differ only in where the beat
    /// frequency comes from: flash derives it from its light frequency, and the
    /// wordless field carries its own, because it has no light to agree with.
    private func setupBinaural(
        enabled: Bool,
        carrier: Double,
        volume: Double,
        beatFrequency: Double
    ) {
        let binaural = BinauralBeatsEngine()
        binaural.carrierFrequency = carrier
        binaural.volume = volume
        binaural.beatFrequency = beatFrequency
        binauralEngine = binaural
        binauralActive = enabled
    }

    /// Loads a track to play underneath a wordless field.
    ///
    /// Reuses `.audioLight`'s player minus the light-sync generation: the field
    /// is not driven by the audio, it just plays underneath.
    ///
    /// The catch is the point of this method. Everywhere else in the player a
    /// failed load means a failed session; here the field is the content and
    /// audio is decoration, so a missing or unreadable file degrades to silence
    /// and the session carries on. See VisualFieldAudioFailure.
    private func setupVisualFieldAudio(audioFile: AudioFile) -> AudioLightSyncPlayer {
        let player = AudioLightSyncPlayer(lightEngine: engine)
        audioLightSyncPlayer = player

        Task {
            do {
                try await player.loadAudio(audioFile: audioFile)
            } catch {
                Log.general.info("Visual field audio unavailable: \(error)")
                audioLightSyncPlayer = nil
                audioUnavailable = true
            }
        }
        return player
    }

    private func setupAudioMode(audioFile: AudioFile) {
        let player = AudioLightSyncPlayer(lightEngine: engine)
        audioLightSyncPlayer = player
        playbackRuntime = AudioPlaybackRuntime(player: player)

        Task {
            do {
                try await player.loadAudio(audioFile: audioFile)
                duration = player.duration
                let resumeDecision = PlaybackResumeDecision(
                    sessionID: audioFile.id.uuidString,
                    duration: player.duration,
                    storedSessionID: storedResumeID(for: audioFile.id.uuidString),
                    storedProgress: storedResumeProgress(for: audioFile.id.uuidString)
                )
                playbackStartType = resumeDecision.startType
                currentTime = resumeDecision.startTime
                player.seek(to: resumeDecision.startTime)
                await checkForLightSession()
            } catch {
                Log.general.info("Failed to load audio: \(error)")
            }
        }
    }

    private func setupPlaylistMode(playlist: Playlist) {
        let controller = PlaylistPlayerController(playlist: playlist, engine: engine)
        playlistController = controller
        playbackRuntime = PlaylistPlaybackRuntime(controller: controller)
    }

    // MARK: - Private: Countdown & Play

    private func startCountdownAndPlay() {
        PerformanceTrace.event("Playback Countdown Start")
        resetLightExposureForNewAttempt()
        analyticsLifecycle.prepareForNewAttempt()
        hasRecordedHistoryForAttempt = false
        hasReportedCreateOutcome = false
        lastPersistedProgressSecond = -1
        interruptionNotice = nil

        // Maximise screen brightness — but only when lights are actually running.
        captureScreenBrightnessIfNeeded()
        if engine.mindMachineEnabled {
            PlatformApplication.screenBrightness = 1.0
        }

        let count = countdownDuration
        // VoiceOver keeps the numerals: they announce progress, and the
        // wordless arc announces nothing. Everyone else gets the threshold.
        let numeric = ThresholdController.prefersNumericCountdown
        usesNumericCountdown = numeric
        countdownMessage = mode.countdownIntroMessage
        countdownValue = numeric ? count : nil
        thresholdController = numeric ? nil : ThresholdController(
            isSuppressed: false,
            motion: PlatformAccessibility.isReduceMotionEnabled ? .reduced : .full,
            duration: Double(count)
        )
        playbackState = .countdown
        haptics.light()

        countdownTask = Task {
            if numeric {
                for tick in stride(from: count - 1, through: 1, by: -1) {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        countdownValue = tick
                    }
                    haptics.light()
                }
                try? await Task.sleep(for: .seconds(1))
            } else {
                // The arc carries the whole budget in one stretch — no
                // per-second ticks, because a pulse every second is the
                // arousal the threshold exists to avoid.
                try? await Task.sleep(for: .seconds(Double(count)))
            }
            guard !Task.isCancelled else { return }
            if let holdMessage = mode.countdownHoldMessage {
                withAnimation(.easeInOut(duration: 0.35)) {
                    countdownValue = nil
                    countdownMessage = holdMessage
                }
                haptics.medium()
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    countdownMessage = nil
                }
                thresholdController = nil
            } else {
                // No held line — the visual field is watched, so the session
                // begins the moment the count ends.
                withAnimation(.easeInOut(duration: 0.35)) {
                    countdownValue = nil
                    countdownMessage = nil
                }
                thresholdController = nil
                haptics.medium()
            }
            beginPlayback()
            // Auto-hide controls
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if playbackState == .playing {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showingControls = false
                }
            }
        }
    }

    /// Brings the session forward when the user taps during the threshold.
    ///
    /// The numeric countdown could not be skipped. The arc can, because
    /// someone who has already settled should not have to sit out ten
    /// seconds they chose for a day they were less settled. Skipping starts
    /// the session early; it does not shorten it.
    func skipCountdown() {
        guard playbackState == .countdown, !usesNumericCountdown else { return }
        PerformanceTrace.event("Playback Countdown Skip")

        countdownTask?.cancel()
        countdownTask = Task {
            // Let the arc's exit interpolation finish so the field opens
            // rather than cutting.
            try? await Task.sleep(for: .seconds(ThresholdChoreography.skipDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                countdownValue = nil
                countdownMessage = nil
            }
            thresholdController = nil
            haptics.medium()
            beginPlayback()
        }
    }

    private func beginPlayback() {
        PerformanceTrace.event("Playback Begin")
        playbackState = .playing
        nowPlaying.updatePlaybackState(.playing)
        interruptionNotice = nil
        if analyticsLifecycle.markStarted() {
            UsageAnalytics.shared.sessionStarted(
                source: sessionSource,
                category: sessionCategory,
                startType: playbackStartType,
                mode: mode.analyticsName
            )
            if let mindMachineMode {
                UsageAnalytics.shared.mindMachineStarted(
                    mode: mindMachineMode,
                    entryPoint: mindMachineEntryPoint ?? .create
                )
                if mindMachineEntryPoint == .create {
                    UsageAnalytics.shared.createStarted(createMode)
                }
            }
            if case .audioLight(let audioFile) = mode {
                Task { await AudioLibraryStore.recordPlayback(audioFileID: audioFile.id) }
            } else if case .session(_, let audioFile?) = mode {
                Task { await AudioLibraryStore.recordPlayback(audioFileID: audioFile.id) }
            }
        }

        playbackRuntime?.begin()
    }

    private func pause() {
        PerformanceTrace.event("Playback Pause")
        playbackState = .paused
        nowPlaying.updatePlaybackState(.paused)

        playbackRuntime?.pause()
        persistPlaybackProgress()
    }

    private func resume() {
        PerformanceTrace.event("Playback Resume")
        playbackState = .playing
        nowPlaying.updatePlaybackState(.playing)
        interruptionNotice = nil

        playbackRuntime?.resume()
    }

    func stopAll(reason: PlaybackEndReason = .userStopped) {
        PerformanceTrace.event("Playback Stop")
        countdownTask?.cancel()
        countdownTask = nil
        PlatformApplication.screenBrightness = savedBrightness
        countdownValue = nil
        countdownMessage = nil
        reportSessionEndedIfNeeded(reason: reason)
        recordSessionHistoryIfNeeded()
        persistPlaybackProgress()

        playbackRuntime?.stop()

        playbackState = .idle
        nowPlaying.deactivate()
    }

    private func handlePlaybackInterruption() {
        reportPlayerLifecycle(.interrupted)
        switch PlaybackRetentionPolicy.interruptionAction(for: playbackState) {
        case .pause:
            pause()
            persistPlaybackProgress()
            showingControls = true
            interruptionNotice = "Paused because audio was interrupted"

        case .cancelPendingStart:
            cancelPendingStart(message: "Start cancelled because audio was interrupted")

        case .none:
            break
        }
    }

    private func cancelPendingStart(message: String) {
        PerformanceTrace.event("Playback Countdown Cancel")
        countdownTask?.cancel()
        countdownTask = nil
        PlatformApplication.screenBrightness = savedBrightness
        countdownValue = nil
        countdownMessage = nil
        playbackState = .idle
        showingControls = true
        interruptionNotice = message
    }

    private func completePlayback() {
        guard playbackState == .playing else { return }
        PerformanceTrace.event("Playback Complete")

        currentTime = duration
        playbackState = .complete
        PlatformApplication.screenBrightness = savedBrightness
        reportSessionEndedIfNeeded(reason: .completed)
        recordSessionHistoryIfNeeded()
        persistPlaybackProgress()

        playbackRuntime?.complete()

        showingControls = true
        nowPlaying.updateProgress(1)
        nowPlaying.updatePlaybackState(.complete)
    }

    private func reportSessionEndedIfNeeded(reason: PlaybackEndReason) {
        guard analyticsLifecycle.markEnded() else { return }

        let fraction: Double?
        if duration > 0 {
            fraction = playbackState == .complete ? 1 : currentTime / duration
        } else {
            fraction = nil
        }
        let resolvedReason: PlaybackEndReason = playbackState == .complete ? .completed : reason
        UsageAnalytics.shared.sessionEnded(
            source: sessionSource,
            category: sessionCategory,
            endReason: resolvedReason,
            fraction: fraction,
            mode: mode.analyticsName
        )
        reportCreateOutcomeIfNeeded()
    }

    private func reportPlayerLifecycle(_ transition: PlaybackLifecycleTransition) {
        guard analyticsLifecycle.hasStarted else { return }
        UsageAnalytics.shared.playerLifecycle(
            transition,
            source: sessionSource,
            category: sessionCategory
        )
    }

    private func reportCreateOutcomeIfNeeded() {
        guard hasReportedCreateOutcome == false,
              let mindMachineMode else { return }
        hasReportedCreateOutcome = true

        let elapsedBucket = ProcessingTimeBucket(seconds: currentTime)
        let meaningful = MindMachineRetentionPolicy.isMeaningful(
            elapsed: currentTime,
            duration: duration
        )
        if meaningful {
            UsageAnalytics.shared.mindMachineCompleted(
                mode: mindMachineMode,
                duration: elapsedBucket
            )
        }
        guard mindMachineEntryPoint == .create else { return }
        if meaningful {
            UsageAnalytics.shared.createCompleted(createMode, duration: elapsedBucket)
        } else {
            UsageAnalytics.shared.createCancelled(createMode, duration: elapsedBucket)
        }
    }

    private var mindMachineMode: MindMachineMode? {
        if let configuredMindMachineMode { return configuredMindMachineMode }
        switch mode {
        case .flashMode:
            return bilateralMode ? MindMachineMode.bilateral : MindMachineMode.flash
        case .colorPulse:
            return MindMachineMode.colorPulse
        case .visualField:
            return MindMachineMode.visualField
        case .session, .audioLight, .playlist:
            return nil
        }
    }

    private var createMode: CreateMode {
        switch mindMachineMode {
        case .bilateral: .bilateral
        case .colorPulse: .colorPulse
        case .visualField: .visualField
        case .flash, .none: .flash
        }
    }

    // MARK: - Private: Timer

    private func startUIUpdateTimer() {
        stopUIUpdateTimer()

        uiUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let intervalMilliseconds = self.uiUpdateIntervalMilliseconds
                if self.playbackState == .playing {
                    self.updateUI(elapsed: Double(intervalMilliseconds) / 1_000)
                }
                try? await Task.sleep(for: .milliseconds(intervalMilliseconds))
            }
        }
    }

    /// Audio clocks are owned by AVAudioPlayer, so the UI only needs enough
    /// samples to keep the scrubber visually fluid. Four updates per second
    /// avoids six redundant full player update groups every second. Manual
    /// visual modes retain 10 Hz because this task is their authoritative clock.
    private var uiUpdateIntervalMilliseconds: Int {
        if case .audioLight = mode { return 250 }
        return 100
    }

    private func stopUIUpdateTimer() {
        uiUpdateTask?.cancel()
        uiUpdateTask = nil
    }

    private func updateUI(elapsed: TimeInterval) {
        guard playbackState != .complete else { return }

        guard let snapshot = playbackRuntime?.snapshot(elapsed: elapsed) else { return }
        currentTime = snapshot.currentTime
        duration = snapshot.duration
        volume = snapshot.volume
        updateLightExposure(elapsed: elapsed)

        switch mode {
        case .session:
            if showingControls || Int(currentTime) % 5 == 0 {
                updatePhase()
            }
            // Sync binaural beat frequency to the current therapeutic frequency
            if binauralActive, let state = lightScorePlayer?.currentState() {
                binauralEngine?.syncBeatFrequency(to: state.frequency)
            }
            persistResumeProgressIfNeeded()

        case .flashMode:
            break

        case .colorPulse:
            break

        case .visualField(let settings, _, _):
            visualFieldFade = VisualFieldFade.multiplier(
                elapsed: currentTime, duration: settings.duration
            )

        case .audioLight:
            persistResumeProgressIfNeeded()

        case .playlist:
            break
        }

        if playbackState == .playing && snapshot.hasReachedEnd {
            completePlayback()
        }

        // Keep mini-player in sync
        nowPlaying.updateProgress(progress)
        nowPlaying.updatePlaybackState(playbackState)
    }

    private func resetLightExposureForNewAttempt() {
        lightExposureBudget = LightExposureBudget(limit: lightExposureBudget.limit)
        lightOutputMultiplier = 1

        guard didReachLightExposureLimit else { return }
        didReachLightExposureLimit = false
        switch mode {
        case .session, .playlist:
            engine.mindMachineEnabled = mode.hasMindMachineToggle
                ? AppSettingsManager.isMindMachineEnabled(defaults: userDefaults)
                : true
        case .flashMode, .colorPulse, .audioLight, .visualField:
            break
        }
    }

    private func updateLightExposure(elapsed: TimeInterval) {
        switch mode {
        case .session, .audioLight, .playlist:
            let reachedLimit = lightExposureBudget.advance(
                by: elapsed,
                whileEmitting: isLightOutputActive
            )
            lightOutputMultiplier = lightExposureBudget.outputMultiplier
            if reachedLimit {
                disableLightOutputAtExposureLimit()
            }

        case .flashMode, .colorPulse:
            lightOutputMultiplier = LightExposureBudget.outputMultiplier(
                remaining: max(0, lightExposureBudget.limit.duration - currentTime)
            )

        case .visualField:
            lightOutputMultiplier = 1
        }
    }

    private var isLightOutputActive: Bool {
        switch mode {
        case .session, .playlist:
            engine.mindMachineEnabled
                && engine.isDrivingOutput
                && engine.isOutputSuspended == false
        case .audioLight:
            lightSyncEnabled
                && engine.isDrivingOutput
                && engine.isOutputSuspended == false
        case .flashMode:
            flashController?.isFlashing == true && flashController?.isPaused == false
        case .colorPulse:
            playbackState == .playing
        case .visualField:
            false
        }
    }

    private func disableLightOutputAtExposureLimit() {
        guard didReachLightExposureLimit == false else { return }
        didReachLightExposureLimit = true
        lightOutputMultiplier = 0

        switch mode {
        case .session:
            // Do not use the persisted preference setter: this cutoff lasts only
            // for the current playback attempt.
            engine.mindMachineEnabled = false
        case .playlist:
            // Do not use the persisted preference setter: this cutoff lasts only
            // for the current playback attempt.
            engine.mindMachineEnabled = false
        case .audioLight:
            lightSyncEnabled = false
            audioLightSyncPlayer?.disableLightSync()
        case .flashMode, .colorPulse, .visualField:
            break
        }

        PlatformApplication.screenBrightness = savedBrightness
        PlatformApplication.keepsScreenAwake = false
    }

    // MARK: - Private: Phase Detection (Session Mode)

    private func updatePhase() {
        guard case .session(let session, _) = mode else { return }
        let progress = currentTime / session.duration_sec
        if progress < 0.2 {
            currentPhase = "Induction Phase"
        } else if progress < 0.8 {
            currentPhase = "Pattern Phase"
        } else {
            currentPhase = "Integration Phase"
        }
    }

    // MARK: - Private: Progress Persistence

    private func persistPlaybackProgress() {
        guard let contentID = resumableContentID, duration > 0 else { return }
        let prog = currentTime / duration
        if prog > 0.01 && prog < 0.99 {
            lastSessionId = contentID
            lastSessionProgress = prog
            playbackProgressStore.save(
                contentID: contentID,
                kind: resumableContentKind,
                title: mode.title,
                progress: prog,
                duration: duration
            )
        } else if prog >= 0.99 {
            playbackProgressStore.clear(contentID: contentID)
            if lastSessionId == contentID {
                lastSessionId = ""
                lastSessionProgress = 0.0
            }
        }
    }

    private func storedResumeID(for contentID: String) -> String {
        playbackProgressStore.snapshot(for: contentID) != nil ? contentID : lastSessionId
    }

    private func storedResumeProgress(for contentID: String) -> Double {
        playbackProgressStore.snapshot(for: contentID)?.progress
            ?? (lastSessionId == contentID ? lastSessionProgress : 0)
    }

    private var resumableContentKind: ResumablePlaybackKind {
        switch mode {
        case .audioLight: .audio
        case .session, .flashMode, .colorPulse, .playlist, .visualField: .session
        }
    }

    private func persistResumeProgressIfNeeded() {
        guard playbackState == .playing else { return }
        let currentSecond = Int(currentTime)
        guard currentSecond >= lastPersistedProgressSecond + 5 else { return }
        lastPersistedProgressSecond = currentSecond
        persistPlaybackProgress()
    }

    private var resumableContentID: String? {
        switch mode {
        case .session(let session, _):
            return session.id.uuidString
        case .audioLight(let audioFile):
            return audioFile.id.uuidString
        case .flashMode, .colorPulse, .playlist, .visualField:
            return nil
        }
    }

    private static func isSaved(mode: PlayerMode, savedSessionStore: SavedSessionStore) -> Bool {
        switch mode {
        case .session(let session, let audioFile):
            audioFile?.favorite ?? savedSessionStore.contains(session.id.uuidString)
        case .audioLight(let audioFile):
            audioFile.favorite
        case .flashMode, .colorPulse, .playlist, .visualField:
            false
        }
    }

    private func prepareRecommendedNextModeIfNeeded() {
        guard didPrepareRecommendation == false else { return }
        didPrepareRecommendation = true

        switch mode {
        case .audioLight(let currentFile), .session(_, let currentFile?):
            Task { [weak self] in
                // ContentView primes this snapshot at launch. Reuse it rather
                // than decoding and repairing the multi-MB library every time
                // the player appears (519 ms in the navigation-memory trace).
                let cache = AudioLibraryCache.shared
                let files: [AudioFile]
                if cache.hasLoaded {
                    files = cache.files
                } else {
                    files = await AudioLibraryStore.loadRepairingStoredFiles()
                    cache.store(files)
                }
                guard let next = LibraryShelfContent
                    .recommendedNext(from: files)
                    .first(where: { $0.id != currentFile.id }) else { return }
                self?.recommendedNextMode = .audioLight(audioFile: next)
            }
        case .session(let currentSession, nil):
            recommendedNextMode = recommendedBuiltInSession(excluding: currentSession.id)
                .map { .session(session: $0, audioFile: nil) }
        case .flashMode, .colorPulse, .playlist, .visualField:
            recommendedNextMode = recommendedBuiltInSession(excluding: nil)
                .map { .session(session: $0, audioFile: nil) }
        }
    }

    private func recommendedBuiltInSession(excluding excludedID: UUID?) -> LightSession? {
        let sessions = LightScoreReader.discoverBundledSessions().compactMap {
            try? LightScoreReader.loadSession(named: $0)
        }
        let candidates = sessions.filter { $0.id != excludedID }
        return PortalRecommender.recommend(from: candidates) ?? candidates.first
    }

    private func recordSessionHistoryIfNeeded() {
        guard analyticsLifecycle.hasStarted, !hasRecordedHistoryForAttempt else { return }

        switch mode {
        case .session, .audioLight:
            break
        case .flashMode(_, _, _, _, _, _, _, let goalDuration):
            guard goalDuration != nil else { return }
        case .visualField(let settings, _, _):
            guard settings.duration != nil else { return }
        case .colorPulse, .playlist:
            return
        }

        hasRecordedHistoryForAttempt = true
        sessionHistory.record(
            sessionName: mode.title,
            category: sessionCategory,
            durationListened: currentTime,
            totalDuration: duration
        )
    }

    private var sessionCategory: String {
        let frequency: Double
        switch mode {
        case .session(let session, _):
            guard let first = session.light_score.first else { return "Trance" }
            frequency = first.frequency
        case .flashMode(let value, _, _, _, _, _, _, _), .colorPulse(let value, _):
            frequency = value
        case .audioLight, .playlist, .visualField:
            return "Trance"
        }

        switch frequency {
        case ..<4.0:  return "Sleep"
        case ..<8.0:  return "Relax"
        case ..<14.0: return "Focus"
        case ..<30.0: return "Energy"
        default:      return "Trance"
        }
    }

    private var sessionSource: SessionSource {
        switch mode {
        case .session(_, let audioFile): audioFile == nil ? .preset : .generated
        case .audioLight:                .generated
        case .flashMode, .colorPulse, .visualField: .mindMachine
        case .playlist:                  .preset
        }
    }

    // MARK: - Private: Light Session Discovery (Audio Mode)

    func checkForLightSession() async {
        guard lightSession == nil, case .audioLight(let file) = mode else { return }
        lightSession = GeneratedSessionStore.shared.load(for: file)
    }

    // MARK: - Private: Binaural

    private func updateBinauralState() {
        if binauralActive && playbackState == .playing {
            binauralEngine?.start()
        } else {
            binauralEngine?.stop()
        }
    }

    // MARK: - Helpers

    func formatTime(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    private func stageLabel(_ stage: AnalysisStage) -> String {
        switch stage {
        case .starting: return "Starting"
        case .transcribing: return "Transcribing"
        case .analyzing: return "Analyzing"
        case .generatingSession: return "Generating"
        case .complete: return "Complete"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Int Clamping Helper

private extension Int {
    func clamped(options: [Int]) -> Int {
        options.contains(self) ? self : (options.first ?? self)
    }
}
