//
//  AudioEnergyAnalyzer.swift
//  Ilumionate
//
//  Analyzes audio files for silence and binaural-beat-only regions
//  at the head and tail, used to optimize playlist crossfade timing.
//

import AVFoundation

// MARK: - Data Types

/// Classification of a dead-time region
enum DeadTimeType: String, Codable {
    case silence   // Near-zero amplitude
    case binaural  // Low-amplitude, steady-state tone (e.g. binaural beat carrier)
    case mixed     // Combination of silence and binaural windows
    case none      // No dead time detected
}

/// Result of dead-time analysis for one audio file
struct DeadTimeProfile: Codable {
    let headDeadTime: TimeInterval
    let tailDeadTime: TimeInterval
    let headClassification: DeadTimeType
    let tailClassification: DeadTimeType
    let analysisDate: Date
}

// MARK: - Analyzer

/// Lightweight analyzer that reads PCM samples from the head and tail of an audio file
/// to detect silence or low-energy steady-state regions (binaural beats).
/// Safe to run on a background thread — no @MainActor requirement.
struct AudioEnergyAnalyzer: Sendable {

    nonisolated init() {}

    struct Config: Sendable {
        /// Duration of each analysis window in seconds
        var windowDuration: TimeInterval = 0.5
        /// Maximum amount of audio to scan from each end
        var scanDuration: TimeInterval = 60.0
        /// RMS threshold below which a window is considered silent (~-46 dB)
        var silenceRMSThreshold: Float = 0.005
        /// RMS threshold for binaural detection (low but non-silent)
        var binauralRMSThreshold: Float = 0.05
        /// Variance threshold — very low variance means a steady-state signal
        var binauralVarianceThreshold: Float = 0.0001

        nonisolated init() {}
    }

    /// Analyze the audio file at `url` and return a dead-time profile.
    nonisolated func analyze(url: URL, config: Config = Config()) throws -> DeadTimeProfile {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(audioFile.length)

        let windowFrames = AVAudioFrameCount(sampleRate * config.windowDuration)
        let scanFrames = min(AVAudioFrameCount(sampleRate * config.scanDuration), totalFrames)

        guard scanFrames > 0, windowFrames > 0 else {
            return DeadTimeProfile(headDeadTime: 0, tailDeadTime: 0,
                                   headClassification: .none, tailClassification: .none,
                                   analysisDate: Date())
        }

        // --- HEAD SCAN ---
        audioFile.framePosition = 0
        let headBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: scanFrames)!
        try audioFile.read(into: headBuffer, frameCount: scanFrames)
        let headResult = scanEdge(buffer: headBuffer, windowFrames: windowFrames,
                                  config: config, fromEnd: false)

        // --- TAIL SCAN ---
        let tailStart = max(0, AVAudioFramePosition(totalFrames) - AVAudioFramePosition(scanFrames))
        audioFile.framePosition = tailStart
        let tailBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: scanFrames)!
        try audioFile.read(into: tailBuffer, frameCount: scanFrames)
        let tailResult = scanEdge(buffer: tailBuffer, windowFrames: windowFrames,
                                  config: config, fromEnd: true)

        return DeadTimeProfile(
            headDeadTime: headResult.duration,
            tailDeadTime: tailResult.duration,
            headClassification: headResult.classification,
            tailClassification: tailResult.classification,
            analysisDate: Date()
        )
    }

    // MARK: - Private

    private struct EdgeResult {
        let duration: TimeInterval
        let classification: DeadTimeType
    }

    private enum WindowClass {
        case silence
        case binaural
        case content
    }

    /// Scan from one edge of the buffer inward, counting consecutive dead windows.
    private nonisolated func scanEdge(
        buffer: AVAudioPCMBuffer,
        windowFrames: AVAudioFrameCount,
        config: Config,
        fromEnd: Bool
    ) -> EdgeResult {
        guard let channelData = buffer.floatChannelData else {
            return EdgeResult(duration: 0, classification: .none)
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        let winSize = Int(windowFrames)

        guard frameCount > 0, winSize > 0 else {
            return EdgeResult(duration: 0, classification: .none)
        }

        let windowCount = frameCount / winSize

        guard windowCount > 0 else {
            return EdgeResult(duration: 0, classification: .none)
        }

        // Classify every window
        var classifications = [WindowClass]()
        classifications.reserveCapacity(windowCount)

        for windowIndex in 0..<windowCount {
            let start = windowIndex * winSize
            let cls = classifyWindow(channelData: channelData, channelCount: channelCount,
                                     start: start, length: winSize, config: config)
            classifications.append(cls)
        }

        // Walk inward from the appropriate edge
        var deadCount = 0
        var hasSilence = false
        var hasBinaural = false

        let indices: any Sequence<Int> = fromEnd
            ? AnySequence((0..<windowCount).reversed())
            : AnySequence(0..<windowCount)

        for windowIndex in indices {
            switch classifications[windowIndex] {
            case .silence:
                deadCount += 1
                hasSilence = true
            case .binaural:
                deadCount += 1
                hasBinaural = true
            case .content:
                break // stop at first content window
            }
            if classifications[windowIndex] == .content { break }
        }

        let duration = Double(deadCount) * config.windowDuration
        let classification: DeadTimeType
        if deadCount == 0 {
            classification = .none
        } else if hasSilence && hasBinaural {
            classification = .mixed
        } else if hasBinaural {
            classification = .binaural
        } else {
            classification = .silence
        }

        return EdgeResult(duration: duration, classification: classification)
    }

    /// Classify a single window of audio samples by computing RMS energy and variance.
    private nonisolated func classifyWindow(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        start: Int,
        length: Int,
        config: Config
    ) -> WindowClass {
        // Average RMS and variance across all channels
        var totalRMS: Float = 0
        var totalVariance: Float = 0

        for channelIndex in 0..<channelCount {
            let samples = channelData[channelIndex]
            var sumSquared: Float = 0
            var sum: Float = 0

            for sampleIndex in start..<(start + length) {
                let sampleValue = samples[sampleIndex]
                let squaredValue = sampleValue * sampleValue
                sumSquared += squaredValue
                sum += squaredValue // sum of squared values for variance calc
            }

            let meanSquared = sumSquared / Float(length)
            let rms = sqrtf(meanSquared)

            // Variance of the squared amplitude (measures how "steady" the signal is)
            let meanSq = sum / Float(length)
            var varianceSum: Float = 0
            for sampleIndex in start..<(start + length) {
                let squaredValue = samples[sampleIndex] * samples[sampleIndex]
                let diff = squaredValue - meanSq
                varianceSum += diff * diff
            }
            let variance = varianceSum / Float(length)

            totalRMS += rms
            totalVariance += variance
        }

        let avgRMS = totalRMS / Float(channelCount)
        let avgVariance = totalVariance / Float(channelCount)

        if avgRMS < config.silenceRMSThreshold {
            return .silence
        }
        if avgRMS < config.binauralRMSThreshold && avgVariance < config.binauralVarianceThreshold {
            return .binaural
        }
        return .content
    }
}
