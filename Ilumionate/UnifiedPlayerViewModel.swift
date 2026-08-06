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

struct PlaybackAnalyticsLifecycle: Equatable {
    private(set) var hasStarted = false
    private(set) var hasEnded = false

    mutating func prepareForNewAttempt() {
        hasStarted = false
        hasEnded = false
    }

    mutating func markStarted() -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }

    mutating func markEnded() -> Bool {
        guard hasStarted, !hasEnded else { return false }
        hasEnded = true
        return true
    }
}

nonisolated struct PlaybackResumeDecision: Equatable, Sendable {
    let startType: PlaybackStartType
    let startTime: TimeInterval

    init(
        sessionID: String,
        duration: TimeInterval,
        storedSessionID: String,
        storedProgress: Double
    ) {
        guard sessionID == storedSessionID,
              duration > 0,
              storedProgress > 0,
              storedProgress < 1 else {
            startType = .fresh
            startTime = 0
            return
        }

        startType = .resumed
        startTime = duration * storedProgress
    }
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
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
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
    var flashFrequency: Double = 10.0
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

        if case .flashMode(let freq, _, let colorTemp, _, _, _, _, _) = mode {
            flashFrequency = freq
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
        switch mode {
        case .session:
            lightScorePlayer?.seek(to: time)
            audioSync?.seek(to: time)
        case .audioLight:
            audioLightSyncPlayer?.seek(to: time)
        case .playlist:
            playlistController?.seek(to: time)
        case .flashMode, .colorPulse, .visualField:
            break
        }
        currentTime = time
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
        switch mode {
        case .session:
            audioSync?.audioVolume = volume
        case .audioLight:
            audioLightSyncPlayer?.setVolume(volume)
        case .playlist:
            playlistController?.setVolume(volume)
        default:
            break
        }
    }

    // MARK: - Light Sync (Audio Mode)

    func toggleLightSync() {
        haptics.medium()

        switch lightSyncStatus {
        case .enabled:
            withAnimation(.easeInOut(duration: 0.4)) { lightSyncEnabled = false }
            audioLightSyncPlayer?.disableLightSync()
        case .ready:
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
        switch mode {
        case .session(let session, let audioFile):
            setupSessionMode(session: session, audioFile: audioFile)

        case .flashMode(let frequency, let intensity, _, let pattern, let binauralEnabled, let binauralCarrier, let binauralVolume, let goalDuration):
            setupFlashMode(frequency: frequency, intensity: intensity, pattern: pattern,
                          binauralEnabled: binauralEnabled, binauralCarrier: binauralCarrier, binauralVolume: binauralVolume)
            duration = goalDuration ?? 0

        case .colorPulse:
            // No controller needed — TimelineView handles rendering
            duration = 0 // infinite

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
            if let audioFile {
                setupVisualFieldAudio(audioFile: audioFile)
            }

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
        duration = session.duration_sec

        engine.attachSession(player: player)
        if !engine.isRunning { engine.start() }
        engine.pause()
        let resumeDecision = PlaybackResumeDecision(
            sessionID: session.id.uuidString,
            duration: session.duration_sec,
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
            audioSync = sync
            Task {
                do {
                    try await sync.loadAudioAsync(from: audioFile.url)
                } catch {
                    Log.general.info("Failed to load session audio: \(error)")
                }
            }
        }
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
    private func setupVisualFieldAudio(audioFile: AudioFile) {
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
    }

    private func setupAudioMode(audioFile: AudioFile) {
        let player = AudioLightSyncPlayer(lightEngine: engine)
        audioLightSyncPlayer = player

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
    }

    // MARK: - Private: Countdown & Play

    private func startCountdownAndPlay() {
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
        countdownMessage = mode.countdownIntroMessage
        countdownValue = count
        playbackState = .countdown
        haptics.light()

        countdownTask = Task {
            for tick in stride(from: count - 1, through: 1, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    countdownValue = tick
                }
                haptics.light()
            }
            try? await Task.sleep(for: .seconds(1))
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
            } else {
                // No held line — the visual field is watched, so the session
                // begins the moment the count ends.
                withAnimation(.easeInOut(duration: 0.35)) {
                    countdownValue = nil
                    countdownMessage = nil
                }
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

    private func beginPlayback() {
        playbackState = .playing
        interruptionNotice = nil
        if analyticsLifecycle.markStarted() {
            UsageAnalytics.shared.sessionStarted(
                source: sessionSource,
                category: sessionCategory,
                startType: playbackStartType
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

        switch mode {
        case .session:
            lightScorePlayer?.play()
            engine.resume()
            if audioSync?.hasAudioLoaded == true { audioSync?.play() }
            if binauralActive { binauralEngine?.start() }

        case .flashMode:
            flashController?.start()
            if binauralActive { binauralEngine?.start() }

        case .visualField:
            // The shader renders itself; only the optional audio needs starting.
            // No light controller is involved at any point.
            if binauralActive { binauralEngine?.start() }
            audioLightSyncPlayer?.play()

        case .colorPulse:
            // TimelineView handles rendering automatically
            break

        case .audioLight:
            audioLightSyncPlayer?.play()

        case .playlist:
            Task { await playlistController?.startPlayback() }
        }
    }

    private func pause() {
        playbackState = .paused

        switch mode {
        case .session:
            lightScorePlayer?.pause()
            engine.pause()
            audioSync?.pause()
            binauralEngine?.pause()
            persistPlaybackProgress()

        case .flashMode:
            flashController?.pause()
            binauralEngine?.pause()

        case .visualField:
            binauralEngine?.pause()
            audioLightSyncPlayer?.pause()

        case .colorPulse:
            break // TimelineView keeps running but we show pause overlay

        case .audioLight:
            audioLightSyncPlayer?.pause()
            persistPlaybackProgress()

        case .playlist:
            playlistController?.pause()
        }
    }

    private func resume() {
        playbackState = .playing
        interruptionNotice = nil

        switch mode {
        case .session:
            lightScorePlayer?.play()
            engine.resume()
            if audioSync?.hasAudioLoaded == true { audioSync?.play() }
            if binauralActive { binauralEngine?.resume() }

        case .flashMode:
            flashController?.resume()
            if binauralActive { binauralEngine?.resume() }

        case .visualField:
            if binauralActive { binauralEngine?.resume() }
            audioLightSyncPlayer?.play()

        case .colorPulse:
            break

        case .audioLight:
            audioLightSyncPlayer?.play()

        case .playlist:
            playlistController?.play()
        }
    }

    func stopAll(reason: PlaybackEndReason = .userStopped) {
        countdownTask?.cancel()
        countdownTask = nil
        PlatformApplication.screenBrightness = savedBrightness
        countdownValue = nil
        countdownMessage = nil
        reportSessionEndedIfNeeded(reason: reason)
        recordSessionHistoryIfNeeded()
        persistPlaybackProgress()

        switch mode {
        case .session:
            lightScorePlayer?.stop()
            engine.detachSession()
            engine.stop()
            audioSync?.stop()
            binauralEngine?.stop()

        case .flashMode:
            flashController?.stop()
            binauralEngine?.stop()

        case .visualField:
            binauralEngine?.stop()
            audioLightSyncPlayer?.stop()

        case .colorPulse:
            break

        case .audioLight:
            audioLightSyncPlayer?.stop()

        case .playlist:
            playlistController?.stop()
        }

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

        currentTime = duration
        playbackState = .complete
        PlatformApplication.screenBrightness = savedBrightness
        reportSessionEndedIfNeeded(reason: .completed)
        recordSessionHistoryIfNeeded()
        persistPlaybackProgress()

        switch mode {
        case .session:
            lightScorePlayer?.pause()
            engine.pause()
            audioSync?.pause()
            binauralEngine?.pause()

        case .flashMode:
            flashController?.stop()
            binauralEngine?.stop()

        case .visualField:
            binauralEngine?.stop()
            audioLightSyncPlayer?.pause()

        case .colorPulse:
            break

        case .audioLight:
            audioLightSyncPlayer?.pause()

        case .playlist:
            playlistController?.pause()
        }

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
            fraction: fraction
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
                self?.updateUI()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopUIUpdateTimer() {
        uiUpdateTask?.cancel()
        uiUpdateTask = nil
    }

    private func updateUI() {
        guard playbackState != .complete else { return }

        switch mode {
        case .session:
            currentTime = lightScorePlayer?.currentTime ?? 0
            if showingControls || Int(currentTime) % 5 == 0 {
                updatePhase()
            }
            // Sync binaural beat frequency to the current therapeutic frequency
            if binauralActive, let state = lightScorePlayer?.currentState() {
                binauralEngine?.syncBeatFrequency(to: state.frequency)
            }
            // Check completion
            persistResumeProgressIfNeeded()
            if PlaybackRetentionPolicy.hasReachedEnd(
                currentTime: currentTime,
                duration: duration,
                state: playbackState
            ) {
                completePlayback()
            }

        case .flashMode:
            currentTime = flashController?.sessionDuration ?? 0
            if PlaybackRetentionPolicy.hasReachedEnd(
                currentTime: currentTime,
                duration: duration,
                state: playbackState
            ) {
                completePlayback()
            }

        case .colorPulse:
            // currentTime tracks how long the pulse has been running
            if playbackState == .playing {
                currentTime += 0.1
            }

        case .visualField(let settings, _, _):
            // Same as colorPulse: nothing else owns a clock here, so the field
            // advances its own and the fade reads off it.
            if playbackState == .playing {
                currentTime += 0.1
            }
            if let player = audioLightSyncPlayer { volume = player.volume }
            visualFieldFade = VisualFieldFade.multiplier(
                elapsed: currentTime, duration: settings.duration
            )
            if VisualFieldFade.isComplete(
                elapsed: currentTime, duration: settings.duration
            ) {
                completePlayback()
            }

        case .audioLight:
            currentTime = audioLightSyncPlayer?.currentTime ?? 0
            duration = audioLightSyncPlayer?.duration ?? 0
            volume = audioLightSyncPlayer?.volume ?? 0.7
            persistResumeProgressIfNeeded()
            // Check completion
            if let player = audioLightSyncPlayer,
               !player.isPlaying,
               PlaybackRetentionPolicy.hasReachedEnd(
                currentTime: currentTime,
                duration: duration,
                state: playbackState
               ) {
                completePlayback()
            }

        case .playlist:
            currentTime = playlistController?.currentTime ?? 0
            duration = playlistController?.currentItemDuration ?? 0
            volume = playlistController?.volume ?? 0.7
        }

        // Keep mini-player in sync
        nowPlaying.updateProgress(progress)
        nowPlaying.updatePlaybackState(playbackState)
    }

    // MARK: - Private: Phase Detection (Session Mode)

    private func updatePhase() {
        guard case .session(let session, _) = mode else { return }
        let progress = currentTime / session.duration_sec
        if progress < 0.2 {
            currentPhase = "Induction Phase"
        } else if progress < 0.8 {
            currentPhase = "Entrainment Phase"
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
                let files = await AudioLibraryStore.loadRepairingStoredFiles()
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
