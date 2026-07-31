//
//  BinauralBeatsEngine.swift
//  Ilumionate
//
//  Real-time binaural beat synthesiser using AVAudioEngine.
//
//  How it works:
//    Left ear:  carrierFrequency Hz (e.g. 200 Hz)
//    Right ear: carrierFrequency + beatFrequency Hz (e.g. 210 Hz)
//  The brain perceives the difference as an auditory beat at beatFrequency (10 Hz),
//  which can entrain neural oscillations toward that target frequency.
//
//  ⚠ Headphones are required — stereo channel separation is essential.
//

import AVFoundation
import CoreAudio
import os
import Synchronization

// MARK: - Audio Render State

/// Mutable state shared between the MainActor setup path and the real-time
/// audio render thread. Cross-thread control values use lock-free atomics so
/// the render callback never takes a lock. Phase/smoothing fields are confined
/// to AVAudioEngine's serial render callback.
private final class AudioRenderState: @unchecked Sendable {
    // Written from main thread, read from render thread
    let targetBeatFreq = Atomic<Double>(10.0)
    let carrierFreq = Atomic<Double>(200.0)
    let targetAmplitude = Atomic<Float>(0.105)  // ~30 % of 0.35 peak

    // Exclusively accessed by the render thread
    var leftPhase: Double = 0
    var rightPhase: Double = 0
    var smoothBeatFreq: Double = 10.0
    var smoothAmplitude: Float = 0
}

// MARK: - Binaural Beats Engine

/// Observable, MainActor-isolated controller for on-device binaural beat generation.
@MainActor
@Observable
final class BinauralBeatsEngine {

    // MARK: Observable State

    private(set) var isPlaying: Bool = false

    /// Beat frequency (Hz) — should mirror the therapeutic / flash frequency.
    var beatFrequency: Double = 10.0 {
        didSet { renderState.targetBeatFreq.store(max(0.5, beatFrequency), ordering: .relaxed) }
    }

    /// Carrier tone sent to the left ear (Hz). Right ear = carrier + beatFrequency.
    /// Typical ranges: 100–200 Hz (delta/theta), 200–300 Hz (alpha/beta).
    var carrierFrequency: Double = 200.0 {
        didSet { renderState.carrierFreq.store(max(50, min(500, carrierFrequency)), ordering: .relaxed) }
    }

    /// Output volume 0…1.
    var volume: Double = 0.5 {
        didSet {
            // Scale to safe listening amplitude: 0.35 max peak (≈ -9 dBFS).
            renderState.targetAmplitude.store(Float(max(0, min(1, volume))) * 0.35, ordering: .relaxed)
        }
    }

    // MARK: Private

    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let renderState = AudioRenderState()
    private var isSetUp = false
    private var fadeOutTask: Task<Void, Never>?

    // MARK: Public Interface

    /// Begin binaural beat playback.
    func start() {
        guard !isPlaying else { return }
        if !isSetUp { setUp() }
        // Restore amplitude — stop() zeros it, so every start must recalculate.
        renderState.targetAmplitude.store(Float(max(0, min(1, volume))) * 0.35, ordering: .relaxed)
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            try audioEngine.start()
            isPlaying = true
        } catch {
            Log.audio.info("[BinauralBeats] Engine start failed: \(error)")
        }
    }

    /// Pause playback by ramping amplitude to zero (no clicks).
    func pause() {
        guard isPlaying else { return }
        renderState.targetAmplitude.store(0, ordering: .relaxed)
        fadeOutTask?.cancel()
        fadeOutTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            audioEngine.stop()
            isPlaying = false
        }
    }

    /// Resume playback after a pause.
    func resume() {
        fadeOutTask?.cancel()
        guard !isPlaying else { return }
        renderState.targetAmplitude.store(Float(max(0, min(1, volume))) * 0.35, ordering: .relaxed)
        do {
            try audioEngine.start()
            isPlaying = true
        } catch {
            Log.audio.info("[BinauralBeats] Resume failed: \(error)")
        }
    }

    /// Stop playback and release resources.
    func stop() {
        fadeOutTask?.cancel()
        audioEngine.stop()
        isPlaying = false
        renderState.targetAmplitude.store(0, ordering: .relaxed)
    }

    /// Convenience — update beat frequency to track the current therapeutic target.
    func syncBeatFrequency(to frequency: Double) {
        beatFrequency = frequency
    }

    // MARK: Engine Setup

    private func setUp() {
        // Configure audio session BEFORE building the engine graph so the
        // output-node format reflects the correct hardware configuration.
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        } catch {
            Log.audio.info("[BinauralBeats] AVAudioSession setup error: \(error)")
        }
        #endif

        let sampleRate: Double = 44100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }

        let state = renderState
        let twoPi = 2.0 * Double.pi

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard ablPointer.count >= 2,
                  let leftRaw = ablPointer[0].mData,
                  let rightRaw = ablPointer[1].mData else { return noErr }

            let leftBuf  = leftRaw.assumingMemoryBound(to: Float.self)
            let rightBuf = rightRaw.assumingMemoryBound(to: Float.self)

            // Smoothing coefficients: ~50 ms for beat freq, ~20 ms for amplitude.
            let freqSmooth: Double = 0.0005
            let ampSmooth: Float  = 0.001

            for frame in 0..<Int(frameCount) {
                // Interpolate beat frequency toward target to avoid audible clicks.
                let targetBeatFreq = state.targetBeatFreq.load(ordering: .relaxed)
                let targetAmplitude = state.targetAmplitude.load(ordering: .relaxed)
                let carrierFreq = state.carrierFreq.load(ordering: .relaxed)
                state.smoothBeatFreq += (targetBeatFreq - state.smoothBeatFreq) * freqSmooth
                state.smoothAmplitude += (targetAmplitude - state.smoothAmplitude) * ampSmooth

                let leftSample  = Float(sin(state.leftPhase))  * state.smoothAmplitude
                let rightSample = Float(sin(state.rightPhase)) * state.smoothAmplitude

                leftBuf[frame]  = leftSample
                rightBuf[frame] = rightSample

                // Advance phase accumulators.
                state.leftPhase  += twoPi * carrierFreq / sampleRate
                state.rightPhase += twoPi * (carrierFreq + state.smoothBeatFreq) / sampleRate

                // Wrap to [0, 2π] to prevent floating-point drift.
                if state.leftPhase  >= twoPi { state.leftPhase  -= twoPi }
                if state.rightPhase >= twoPi { state.rightPhase -= twoPi }
            }
            return noErr
        }

        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        audioEngine.mainMixerNode.outputVolume = 1.0

        sourceNode = node
        isSetUp = true
    }
}
