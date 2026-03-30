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

// MARK: - Audio Render State

/// Mutable state shared between the MainActor setup path and the real-time
/// audio render thread.  All properties are either:
///   • written only from one thread (phase accumulators — audio thread only), or
///   • single-instruction scalar writes on ARM64 (Double/Float — safe in practice).
/// Marked @unchecked Sendable to satisfy Swift 6 strict concurrency.
private final class AudioRenderState: @unchecked Sendable {
    // Written from main thread, read from render thread
    var targetBeatFreq: Double = 10.0
    var carrierFreq: Double = 200.0
    var targetAmplitude: Float = 0.105  // ~30 % of 0.35 peak

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
        didSet { renderState.targetBeatFreq = max(0.5, beatFrequency) }
    }

    /// Carrier tone sent to the left ear (Hz). Right ear = carrier + beatFrequency.
    /// Typical ranges: 100–200 Hz (delta/theta), 200–300 Hz (alpha/beta).
    var carrierFrequency: Double = 200.0 {
        didSet { renderState.carrierFreq = max(50, min(500, carrierFrequency)) }
    }

    /// Output volume 0…1.
    var volume: Double = 0.5 {
        didSet {
            // Scale to safe listening amplitude: 0.35 max peak (≈ -9 dBFS).
            renderState.targetAmplitude = Float(max(0, min(1, volume))) * 0.35
        }
    }

    // MARK: Private

    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let renderState = AudioRenderState()
    private var isSetUp = false

    // MARK: Public Interface

    /// Begin binaural beat playback.
    func start() {
        guard !isPlaying else { return }
        if !isSetUp { setUp() }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try audioEngine.start()
            isPlaying = true
        } catch {
            print("[BinauralBeats] Engine start failed: \(error)")
        }
    }

    /// Pause playback by ramping amplitude to zero (no clicks).
    func pause() {
        guard isPlaying else { return }
        renderState.targetAmplitude = 0
        // Stop engine after the amplitude has faded (≈ 150 ms)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            audioEngine.stop()
            isPlaying = false
        }
    }

    /// Resume playback after a pause.
    func resume() {
        guard !isPlaying else { return }
        renderState.targetAmplitude = Float(max(0, min(1, volume))) * 0.35
        do {
            try audioEngine.start()
            isPlaying = true
        } catch {
            print("[BinauralBeats] Resume failed: \(error)")
        }
    }

    /// Stop playback and release resources.
    func stop() {
        audioEngine.stop()
        isPlaying = false
        renderState.smoothAmplitude = 0
        renderState.targetAmplitude = 0
    }

    /// Convenience — update beat frequency to track the current therapeutic target.
    func syncBeatFrequency(to frequency: Double) {
        beatFrequency = frequency
    }

    // MARK: Engine Setup

    private func setUp() {
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
                state.smoothBeatFreq += (state.targetBeatFreq - state.smoothBeatFreq) * freqSmooth
                state.smoothAmplitude += (state.targetAmplitude - state.smoothAmplitude) * ampSmooth

                let leftSample  = Float(sin(state.leftPhase))  * state.smoothAmplitude
                let rightSample = Float(sin(state.rightPhase)) * state.smoothAmplitude

                leftBuf[frame]  = leftSample
                rightBuf[frame] = rightSample

                // Advance phase accumulators.
                state.leftPhase  += twoPi * state.carrierFreq / sampleRate
                state.rightPhase += twoPi * (state.carrierFreq + state.smoothBeatFreq) / sampleRate

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

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
        } catch {
            print("[BinauralBeats] AVAudioSession setup error: \(error)")
        }
    }
}
