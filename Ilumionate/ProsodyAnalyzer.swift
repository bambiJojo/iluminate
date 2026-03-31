//
//  ProsodyAnalyzer.swift
//  Ilumionate
//
//  Extracts audio-level prosodic features from the raw audio signal and
//  WhisperKit transcript timing. These features — speech rate, volume,
//  pitch contour, and pause map — drive adaptive light scoring in the
//  SessionGenerator, making sessions respond to the hypnotist's actual
//  vocal delivery rather than just their words.
//
//  Pipeline:
//   1. Read PCM audio data via AVFoundation.
//   2. Compute per-window RMS energy (volume curve).
//   3. Estimate F0 pitch via autocorrelation (Accelerate/vDSP).
//   4. Derive speech rate from WhisperKit word timestamps.
//   5. Detect and classify pauses from transcript gaps + RMS silence.
//   6. Return a ProsodicProfile consumed by downstream analysis.
//
//  All methods are nonisolated and safe to run on a background thread.
//

import AVFoundation
import Accelerate
import Foundation

// MARK: - Configuration

extension ProsodyAnalyzer {

    struct Config: Sendable {
        /// Duration of each analysis window in seconds.
        var windowDuration: TimeInterval = 3.0

        /// RMS threshold below which a window is considered silent.
        var silenceThreshold: Float = 0.008

        /// Minimum pause duration (seconds) to record.
        var minPauseDuration: TimeInterval = 1.0

        /// Pause durations that classify as "deliberate" (therapeutic intent).
        var deliberatePauseMin: TimeInterval = 3.0

        /// Pause durations that classify as "extended" (music-only or deep silence).
        var extendedPauseMin: TimeInterval = 5.0

        /// Minimum F0 frequency for pitch detection (Hz). Below this is likely noise.
        var minPitchHz: Double = 70.0

        /// Maximum F0 frequency for pitch detection (Hz). Above this is unlikely voice.
        var maxPitchHz: Double = 400.0
    }

    /// Context for pitch estimation, bundled to reduce parameter count.
    /// Not Sendable — holds raw pointers valid only within `analyze()`.
    struct PitchEstimationContext {
        let samples: UnsafePointer<Float>
        let length: Int
        let sampleRate: Double
        let config: Config
    }
}

// MARK: - Analyzer

/// Extracts prosodic features from audio files for adaptive light session generation.
///
/// This analyzer operates purely on the audio signal and WhisperKit timestamps —
/// no AI model is required. It produces a `ProsodicProfile` that captures how
/// the speaker's delivery changes over time: pace, volume, pitch, and pauses.
struct ProsodyAnalyzer: Sendable {

    /// Context for per-window curve computation, bundled to reduce parameter count.
    struct WindowAnalysisContext {
        let channelData: UnsafePointer<UnsafeMutablePointer<Float>>
        let channelCount: Int
        let frameCount: Int
        let windowFrames: Int
        let sampleRate: Double
        let config: Config
        let wordTimestamps: [WordTimestamp]
    }

    /// Per-window analysis results.
    struct WindowCurves {
        var volume: [Double]
        var pitch: [Double]
        var speechRate: [Double]
        var speechSilenceRatio: [Double]
    }

    /// Analyze an audio file and produce a prosodic profile.
    ///
    /// - Parameters:
    ///   - url: File URL of the audio to analyse.
    ///   - segments: WhisperKit transcript segments (for speech rate and pause context).
    ///   - config: Analysis configuration.
    /// - Returns: A `ProsodicProfile` with per-window curves and detected pauses.
    nonisolated func analyze(
        url: URL,
        segments: [AudioTranscriptionSegment],
        config: Config = Config()
    ) throws -> ProsodicProfile {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let totalDuration = Double(totalFrames) / sampleRate
        let windowFrames = AVAudioFrameCount(sampleRate * config.windowDuration)

        // Read all samples into a buffer
        audioFile.framePosition = 0
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            return emptyProfile(windowDuration: config.windowDuration, totalDuration: totalDuration)
        }
        try audioFile.read(into: buffer, frameCount: totalFrames)

        // Use actual frames read (may be fewer than requested for truncated files)
        let actualFrames = Int(buffer.frameLength)
        let actualDuration = Double(actualFrames) / sampleRate

        guard let channelData = buffer.floatChannelData, actualFrames > 0 else {
            return emptyProfile(windowDuration: config.windowDuration, totalDuration: totalDuration)
        }

        let wordTimestamps = HypnosisPhaseAnalyzer()
            .approximateWordTimestamps(from: segments)

        let windowContext = WindowAnalysisContext(
            channelData: channelData,
            channelCount: Int(format.channelCount),
            frameCount: actualFrames,
            windowFrames: Int(windowFrames),
            sampleRate: sampleRate,
            config: config,
            wordTimestamps: wordTimestamps
        )
        let windowCount = max(1, Int(ceil(actualDuration / config.windowDuration)))
        let curves = computeWindowCurves(context: windowContext, windowCount: windowCount)

        // Detect pauses from transcript gaps
        let pauseContext = PauseDetectionContext(
            segments: segments,
            volumeCurve: curves.volume,
            windowDuration: config.windowDuration,
            totalDuration: actualDuration,
            config: config
        )
        let pauses = detectPauses(context: pauseContext)

        return ProsodicProfile(
            windowDuration: config.windowDuration,
            speechRateCurve: curves.speechRate,
            volumeCurve: curves.volume,
            pitchCurve: curves.pitch,
            speechSilenceRatio: curves.speechSilenceRatio,
            pauses: pauses,
            totalDuration: actualDuration
        )
    }

    /// Computes per-window volume, pitch, speech rate, and silence ratio curves.
    private nonisolated func computeWindowCurves(
        context: WindowAnalysisContext,
        windowCount: Int
    ) -> WindowCurves {
        var curves = WindowCurves(
            volume: [Double](repeating: 0, count: windowCount),
            pitch: [Double](repeating: 0, count: windowCount),
            speechRate: [Double](repeating: 0, count: windowCount),
            speechSilenceRatio: [Double](repeating: 0, count: windowCount)
        )

        for windowIndex in 0..<windowCount {
            let startFrame = windowIndex * context.windowFrames
            let endFrame = min(startFrame + context.windowFrames, context.frameCount)
            let length = endFrame - startFrame
            guard length > 0 else { continue }

            // Volume: RMS energy averaged across channels, normalised 0–1
            let rms = computeRMS(
                channelData: context.channelData,
                channelCount: context.channelCount,
                start: startFrame,
                length: length
            )
            curves.volume[windowIndex] = Double(min(rms / 0.15, 1.0))

            // Pitch: autocorrelation-based F0 on the loudest channel
            // (avoids wrong results for stereo with hard-panned voice)
            var bestChannel = 0
            if context.channelCount > 1 {
                var bestRMS: Float = 0
                for chan in 0..<context.channelCount {
                    let ptr = context.channelData[chan].advanced(by: startFrame)
                    var sq: Float = 0
                    vDSP_svesq(ptr, 1, &sq, vDSP_Length(length))
                    if sq > bestRMS { bestRMS = sq; bestChannel = chan }
                }
            }
            let pitchCtx = PitchEstimationContext(
                samples: context.channelData[bestChannel].advanced(by: startFrame),
                length: length,
                sampleRate: context.sampleRate,
                config: context.config
            )
            curves.pitch[windowIndex] = estimatePitch(context: pitchCtx)

            // Speech rate: words per minute in this window
            let windowStart = Double(windowIndex) * context.config.windowDuration
            let windowEnd = windowStart + context.config.windowDuration
            let actualWindowDur = Double(length) / context.sampleRate
            let wordsInWindow = context.wordTimestamps.filter {
                $0.startTime >= windowStart && $0.startTime < windowEnd
            }
            curves.speechRate[windowIndex] = Double(wordsInWindow.count) / actualWindowDur * 60.0

            // Speech/silence ratio: fraction of window with speech
            let speechTime = wordsInWindow.reduce(0.0) { $0 + $1.duration }
            curves.speechSilenceRatio[windowIndex] = min(1.0, speechTime / actualWindowDur)
        }

        return curves
    }

    // MARK: - RMS Energy

    /// Compute RMS energy for a window of audio, averaged across channels.
    private nonisolated func computeRMS(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        start: Int,
        length: Int
    ) -> Float {
        var totalRMS: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel].advanced(by: start)
            var sumSquared: Float = 0
            vDSP_svesq(samples, 1, &sumSquared, vDSP_Length(length))
            totalRMS += sqrtf(sumSquared / Float(length))
        }

        return totalRMS / Float(channelCount)
    }

    // MARK: - Pitch Estimation (Autocorrelation)

    /// Estimates fundamental frequency (F0) using autocorrelation via vDSP.
    ///
    /// The autocorrelation method finds the dominant periodicity in the signal:
    /// 1. Compute the autocorrelation of the window.
    /// 2. Find the first peak after the zero-lag peak.
    /// 3. Convert the lag of that peak to Hz: F0 = sampleRate / lag.
    ///
    /// Returns 0 if no clear pitch is detected (unvoiced/silent segment).
    private nonisolated func estimatePitch(
        context: PitchEstimationContext
    ) -> Double {
        let samples = context.samples
        let length = context.length
        let sampleRate = context.sampleRate

        // Skip very short windows
        guard length > 256 else { return 0 }

        let maxLag = min(length, Int(sampleRate / context.config.minPitchHz))
        let minLag = max(1, Int(sampleRate / context.config.maxPitchHz))
        guard maxLag > minLag else { return 0 }

        // Compute autocorrelation for lags in the voice frequency range
        var autocorrelation = [Float](repeating: 0, count: maxLag - minLag)
        for lagIndex in 0..<autocorrelation.count {
            let lag = minLag + lagIndex
            let overlapLength = length - lag
            guard overlapLength > 0 else {
                autocorrelation[lagIndex] = 0
                continue
            }
            var dot: Float = 0
            vDSP_dotpr(
                samples, 1,
                samples.advanced(by: lag), 1,
                &dot,
                vDSP_Length(overlapLength)
            )
            autocorrelation[lagIndex] = dot / Float(overlapLength)
        }

        // Find the peak in the autocorrelation
        guard !autocorrelation.isEmpty else { return 0 }
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(autocorrelation, 1, &maxVal, &maxIdx, vDSP_Length(autocorrelation.count))

        // Validate: the peak must be significantly above baseline
        var meanVal: Float = 0
        vDSP_meanv(autocorrelation, 1, &meanVal, vDSP_Length(autocorrelation.count))
        guard maxVal > meanVal * 1.5, maxVal > 0.001 else { return 0 }

        let bestLag = minLag + Int(maxIdx)
        guard bestLag > 0 else { return 0 }
        return sampleRate / Double(bestLag)
    }
}

// MARK: - Protocol Conformance

extension ProsodyAnalyzer: ProsodyAnalyzingService {}

// MARK: - AnalyzerConfig Bridge

extension ProsodyAnalyzer.Config {
    /// Creates a `ProsodyAnalyzer.Config` from the centralized `AnalyzerConfig.Prosody`.
    /// `silenceThreshold`, `minPitchHz`, and `maxPitchHz` are hardware/physiology
    /// constants that are not tuned by the optimizer.
    init(from analyzerConfig: AnalyzerConfig.Prosody) {
        self.init(
            windowDuration: analyzerConfig.speechRateWindowSeconds,
            silenceThreshold: 0.008,
            minPauseDuration: analyzerConfig.pauseThresholdSeconds,
            deliberatePauseMin: analyzerConfig.deliberatePauseMinSeconds,
            extendedPauseMin: analyzerConfig.musicOnlyPauseMinSeconds
        )
    }
}
