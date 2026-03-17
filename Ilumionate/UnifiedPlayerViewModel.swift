//
//  UnifiedPlayerViewModel.swift
//  Ilumionate
//
//  Central view model coordinating all player modes through existing controllers.
//

import SwiftUI
import AVFoundation

// MARK: - Playback State

enum PlaybackState: Equatable {
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

    // MARK: - Universal Playback State

    private(set) var playbackState: PlaybackState = .idle
    private(set) var countdownValue: Int? = nil
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var showingControls = true
    var showingSafetyWarning = false

    // MARK: - Countdown Setting

    @ObservationIgnored
    private var countdownDuration: Int {
        UserDefaults.standard.integer(forKey: "countdownDuration").clamped(options: [1, 3, 10])
    }

    // MARK: - Session Mode State

    private var lightScorePlayer: LightScorePlayer?
    private var audioSync: AudioSyncController?
    var currentPhase = "Induction Phase"
    var isSyncEnabled = true

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
        get { UserDefaults.standard.string(forKey: "lastSessionId") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastSessionId") }
    }

    @ObservationIgnored
    private var lastSessionProgress: Double {
        get { UserDefaults.standard.double(forKey: "lastSessionProgress") }
        set { UserDefaults.standard.set(newValue, forKey: "lastSessionProgress") }
    }

    // MARK: - Safety Warnings

    @ObservationIgnored
    private var hasSeenFlashWarning: Bool {
        get { UserDefaults.standard.bool(forKey: "hasSeenFlashWarning") }
        set { UserDefaults.standard.set(newValue, forKey: "hasSeenFlashWarning") }
    }

    @ObservationIgnored
    private var hasSeenLightSyncWarning: Bool {
        get { UserDefaults.standard.bool(forKey: "hasSeenLightSyncWarning") }
        set { UserDefaults.standard.set(newValue, forKey: "hasSeenLightSyncWarning") }
    }

    // MARK: - Private

    private var uiUpdateTimer: Timer?
    private var savedBrightness: CGFloat = 1.0
    private var hasStarted = false

    // MARK: - Init

    init(mode: PlayerMode, engine: LightEngine) {
        self.mode = mode
        self.engine = engine

        if case .flashMode(let freq, _, let colorTemp, _, _, _, _) = mode {
            flashFrequency = freq
            flashColorTemperature = colorTemp
        }

        showingSafetyWarning = mode.requiresSafetyWarning && !hasSeenFlashWarning
    }

    // MARK: - Lifecycle

    func onAppear() {
        setupMode()
        startUIUpdateTimer()
    }

    func onDisappear() {
        stopAll()
        stopUIUpdateTimer()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        TranceHaptics.shared.medium()

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
            seekToStart()
            startCountdownAndPlay()
        }
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
        case .flashMode, .colorPulse:
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
        TranceHaptics.shared.medium()

        switch lightSyncStatus {
        case .enabled:
            withAnimation(.easeInOut(duration: 0.4)) { lightSyncEnabled = false }
            audioLightSyncPlayer?.disableLightSync()
        case .ready:
            guard let session = lightSession else { return }
            if hasSeenLightSyncWarning {
                enableLightSync(session: session)
            } else {
                // The view should show the warning alert
            }
        case .analyzing:
            break
        case .queued(let position):
            if position > 1, case .audioLight(let file) = mode {
                AnalysisStateManager.shared.prioritizeInQueue(audioFile: file)
            }
        case .unavailable:
            if case .audioLight(let file) = mode {
                Task { await AnalysisStateManager.shared.queueForAnalysis(file) }
            }
        }
    }

    func enableLightSync(session: LightSession) {
        hasSeenLightSyncWarning = true
        withAnimation(.easeInOut(duration: 0.4)) { lightSyncEnabled = true }
        audioLightSyncPlayer?.enableLightSync(lightSession: session)
    }

    var lightSyncStatus: LightSyncStatus {
        if lightSyncEnabled { return .enabled }
        if lightSession != nil { return .ready }

        guard case .audioLight(let file) = mode else { return .unavailable }

        let manager = AnalysisStateManager.shared
        if let current = manager.currentAnalysis,
           current.audioFile.id == file.id {
            return .analyzing(progress: current.progress, stage: stageLabel(current.stage))
        }
        let pos = manager.queuePosition(for: file)
        if pos > 0 { return .queued(position: pos) }
        return .unavailable
    }

    // MARK: - Bilateral / Binaural (Flash Mode)

    func toggleBilateral() {
        bilateralMode.toggle()
        TranceHaptics.shared.medium()
    }

    func toggleBinaural() {
        binauralActive.toggle()
        TranceHaptics.shared.medium()
    }

    func setDriftRate(_ rate: Double) {
        bilateralDriftRate = rate
        TranceHaptics.shared.light()
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
        case .flashMode, .colorPulse, .playlist:
            return true
        case .audioLight:
            return lightSyncEnabled
        case .session:
            return false
        }
    }

    var labelColor: Color { useDarkChrome ? .white : .textPrimary }
    var secondaryLabelColor: Color { useDarkChrome ? .white.opacity(0.7) : .textSecondary }
    var accentColor: Color { useDarkChrome ? .white : .roseGold }

    // MARK: - Private: Setup

    private func setupMode() {
        switch mode {
        case .session(let session, let audioFile):
            setupSessionMode(session: session, audioFile: audioFile)

        case .flashMode(let frequency, let intensity, _, let pattern, let binauralEnabled, let binauralCarrier, let binauralVolume):
            setupFlashMode(frequency: frequency, intensity: intensity, pattern: pattern,
                          binauralEnabled: binauralEnabled, binauralCarrier: binauralCarrier, binauralVolume: binauralVolume)

        case .colorPulse:
            // No controller needed — TimelineView handles rendering
            duration = 0 // infinite

        case .audioLight(let audioFile):
            setupAudioMode(audioFile: audioFile)

        case .playlist(let playlist):
            setupPlaylistMode(playlist: playlist)
        }
    }

    private func setupSessionMode(session: LightSession, audioFile: AudioFile?) {
        let player = LightScorePlayer(session: session)
        lightScorePlayer = player
        duration = session.duration_sec

        engine.attachSession(player: player)
        if !engine.isRunning { engine.start() }
        engine.pause()
        player.seek(to: 0.0)

        if let audioFile {
            let sync = AudioSyncController()
            audioSync = sync
            Task {
                do {
                    try await sync.loadAudioAsync(from: audioFile.url)
                } catch {
                    print("Failed to load session audio: \(error)")
                }
            }
        }
    }

    private func setupFlashMode(frequency: Double, intensity: Double, pattern: MindMachineModel.LightPattern,
                                binauralEnabled: Bool, binauralCarrier: Double, binauralVolume: Double) {
        let controller = FlashController(frequency: frequency, intensity: intensity, pattern: pattern)
        flashController = controller
        duration = 0 // infinite

        if binauralEnabled {
            let binaural = BinauralBeatsEngine()
            binaural.carrierFrequency = binauralCarrier
            binaural.volume = binauralVolume
            binaural.beatFrequency = frequency
            binauralEngine = binaural
            binauralActive = true
        }
    }

    private func setupAudioMode(audioFile: AudioFile) {
        let player = AudioLightSyncPlayer(lightEngine: engine)
        audioLightSyncPlayer = player

        Task {
            do {
                try await player.loadAudio(audioFile: audioFile)
                duration = player.duration
                await checkForLightSession()
            } catch {
                print("Failed to load audio: \(error)")
            }
        }
    }

    private func setupPlaylistMode(playlist: Playlist) {
        let controller = PlaylistPlayerController(playlist: playlist, engine: engine)
        playlistController = controller
    }

    // MARK: - Private: Countdown & Play

    private func startCountdownAndPlay() {
        // Maximise screen brightness
        savedBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1.0

        hasStarted = true
        let count = countdownDuration
        countdownValue = count
        playbackState = .countdown
        TranceHaptics.shared.light()

        Task {
            for tick in stride(from: count - 1, through: 1, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        countdownValue = tick
                    }
                    TranceHaptics.shared.light()
                }
            }
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    countdownValue = nil
                }
                TranceHaptics.shared.medium()
                beginPlayback()
            }
            // Auto-hide controls
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                if playbackState == .playing {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showingControls = false
                    }
                }
            }
        }
    }

    private func beginPlayback() {
        playbackState = .playing

        switch mode {
        case .session:
            lightScorePlayer?.play()
            engine.resume()
            if audioSync?.hasAudioLoaded == true { audioSync?.play() }

        case .flashMode:
            flashController?.start()
            if binauralActive { binauralEngine?.start() }

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
            saveProgress()

        case .flashMode:
            flashController?.pause()
            binauralEngine?.pause()

        case .colorPulse:
            break // TimelineView keeps running but we show pause overlay

        case .audioLight:
            audioLightSyncPlayer?.pause()

        case .playlist:
            playlistController?.pause()
        }
    }

    private func resume() {
        playbackState = .playing

        switch mode {
        case .session:
            lightScorePlayer?.play()
            engine.resume()
            if audioSync?.hasAudioLoaded == true { audioSync?.play() }

        case .flashMode:
            flashController?.resume()
            if binauralActive { binauralEngine?.resume() }

        case .colorPulse:
            break

        case .audioLight:
            audioLightSyncPlayer?.play()

        case .playlist:
            playlistController?.play()
        }
    }

    private func seekToStart() {
        seek(to: 0)
    }

    func stopAll() {
        UIScreen.main.brightness = savedBrightness
        countdownValue = nil

        switch mode {
        case .session:
            saveProgress()
            lightScorePlayer?.stop()
            engine.detachSession()
            engine.stop()
            audioSync?.stop()

        case .flashMode:
            flashController?.stop()
            binauralEngine?.stop()

        case .colorPulse:
            break

        case .audioLight:
            audioLightSyncPlayer?.stop()

        case .playlist:
            playlistController?.stop()
        }

        playbackState = .idle
    }

    // MARK: - Private: Timer

    private func startUIUpdateTimer() {
        stopUIUpdateTimer()

        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateUI()
            }
        }
        RunLoop.main.add(uiUpdateTimer!, forMode: .common)
    }

    private func stopUIUpdateTimer() {
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = nil
    }

    private func updateUI() {
        switch mode {
        case .session:
            currentTime = lightScorePlayer?.currentTime ?? 0
            if showingControls || Int(currentTime) % 5 == 0 {
                updatePhase()
            }
            // Check completion
            if let session = lightScorePlayer?.session,
               currentTime >= session.duration_sec - 0.5,
               playbackState == .playing {
                playbackState = .complete
                stopAll()
            }

        case .flashMode:
            currentTime = flashController?.sessionDuration ?? 0

        case .colorPulse:
            // currentTime tracks how long the pulse has been running
            if playbackState == .playing {
                currentTime += 0.1
            }

        case .audioLight:
            currentTime = audioLightSyncPlayer?.currentTime ?? 0
            duration = audioLightSyncPlayer?.duration ?? 0
            volume = audioLightSyncPlayer?.volume ?? 0.7
            // Check completion
            if let player = audioLightSyncPlayer,
               !player.isPlaying && playbackState == .playing && currentTime >= duration - 0.5 {
                playbackState = .complete
            }

        case .playlist:
            currentTime = playlistController?.currentTime ?? 0
            duration = playlistController?.currentItemDuration ?? 0
            volume = playlistController?.volume ?? 0.7
        }
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

    // MARK: - Private: Progress Persistence (Session Mode)

    private func saveProgress() {
        guard case .session(let session, _) = mode else { return }
        guard session.duration_sec > 0 else { return }
        let listenedDuration = currentTime
        let prog = listenedDuration / session.duration_sec
        if prog > 0.01 && prog < 0.99 {
            lastSessionId = session.id.uuidString
            lastSessionProgress = prog
        } else if prog >= 0.99 {
            lastSessionId = ""
            lastSessionProgress = 0.0
        }
        SessionHistoryManager.shared.record(
            sessionName: session.displayName,
            category: sessionCategory,
            durationListened: listenedDuration,
            totalDuration: session.duration_sec
        )
    }

    private var sessionCategory: String {
        guard case .session(let session, _) = mode,
              let first = session.light_score.first else { return "Trance" }
        switch first.frequency {
        case ..<4.0:  return "Sleep"
        case ..<8.0:  return "Relax"
        case ..<14.0: return "Focus"
        case ..<30.0: return "Energy"
        default:      return "Trance"
        }
    }

    // MARK: - Private: Light Session Discovery (Audio Mode)

    func checkForLightSession() async {
        guard lightSession == nil, case .audioLight(let file) = mode else { return }
        let sessionsURL = URL.documentsDirectory.appending(path: "GeneratedSessions")
        let baseName = file.filename
            .replacing(".mp3", with: "").replacing(".m4a", with: "").replacing(".wav", with: "")
        let fileURL = sessionsURL.appending(path: "\(baseName)_session.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        if let data = try? Data(contentsOf: fileURL),
           let session = try? JSONDecoder().decode(LightSession.self, from: data) {
            lightSession = session
        }
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
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
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
