//
//  BackgroundToneAnalyzer.swift
//  LumeLabel
//
//  Experimental, transcript-free boundary evidence for the labeling tool.
//  Stereo difference suppresses narration that is mixed equally into both
//  channels; a low-resolution spectrum then describes the remaining bed.
//


import Accelerate
import AVFoundation
import Foundation

nonisolated struct BackgroundToneCandidate: Identifiable, Sendable, Equatable {
    let time: TimeInterval
    let strength: Double

    var id: TimeInterval { time }
}

nonisolated struct BackgroundToneNoveltySample: Sendable, Equatable {
    let time: TimeInterval
    let strength: Double
}

nonisolated struct BackgroundToneAnalysis: Sendable, Equatable {
    enum Source: String, Sendable {
        case stereoDifference
        case fullMix

        var displayName: String {
            switch self {
            case .stereoDifference: "stereo background"
            case .fullMix: "full mix"
            }
        }
    }

    let candidates: [BackgroundToneCandidate]
    let novelty: [BackgroundToneNoveltySample]
    let source: Source
    let analyzedDuration: TimeInterval
}

nonisolated enum BackgroundToneAnalyzer {
    struct Configuration: Sendable, Equatable {
        var frameDuration: TimeInterval
        var fingerprintSize: Int
        var bandCount: Int
        var kernelSize: Int
        var minimumCandidateSpacing: TimeInterval
        var edgeExclusion: TimeInterval
        var minimumNovelty: Double
        var minimumProminence: Double
        var minimumStereoDifferenceRatio: Double

        init(
            frameDuration: TimeInterval = 3,
            fingerprintSize: Int = 4_096,
            bandCount: Int = 24,
            kernelSize: Int = 10,
            minimumCandidateSpacing: TimeInterval = 60,
            edgeExclusion: TimeInterval = 18,
            minimumNovelty: Double = 0.12,
            minimumProminence: Double = 0.04,
            minimumStereoDifferenceRatio: Double = 0.02
        ) {
            self.frameDuration = frameDuration
            self.fingerprintSize = fingerprintSize
            self.bandCount = bandCount
            self.kernelSize = kernelSize
            self.minimumCandidateSpacing = minimumCandidateSpacing
            self.edgeExclusion = edgeExclusion
            self.minimumNovelty = minimumNovelty
            self.minimumProminence = minimumProminence
            self.minimumStereoDifferenceRatio = minimumStereoDifferenceRatio
        }

        static let labelingExperiment = Configuration()
    }

    private struct RawFrame {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let fullMix: [Double]
        let stereoDifference: [Double]
        let fullMixRMS: Double
        let stereoDifferenceRMS: Double
    }

    static func analyze(
        audioURL: URL,
        configuration: Configuration = .labelingExperiment
    ) throws -> BackgroundToneAnalysis {
        let configuration = sanitized(configuration)
        let audioFile = try AVAudioFile(forReading: audioURL)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, format.channelCount > 0 else {
            throw analysisError("The audio stream has no readable channels.")
        }

        let requestedFrames = max(
            1,
            AVAudioFrameCount((configuration.frameDuration * sampleRate).rounded())
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: requestedFrames
        ) else {
            throw analysisError("LumeLabel could not allocate an audio analysis buffer.")
        }
        let fftLog2 = vDSP_Length(configuration.fingerprintSize.trailingZeroBitCount)
        guard let fftSetup = vDSP_create_fftsetupD(fftLog2, FFTRadix(kFFTRadix2)) else {
            throw analysisError("LumeLabel could not prepare spectral analysis.")
        }
        defer { vDSP_destroy_fftsetupD(fftSetup) }

        var rawFrames: [RawFrame] = []
        var startTime: TimeInterval = 0

        while audioFile.framePosition < audioFile.length {
            try Task.checkCancellation()
            let remaining = audioFile.length - audioFile.framePosition
            let count = AVAudioFrameCount(min(AVAudioFramePosition(requestedFrames), remaining))
            try audioFile.read(into: buffer, frameCount: count)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { break }
            guard let channels = buffer.floatChannelData else {
                throw analysisError("The decoded audio is not floating-point PCM.")
            }

            let duration = Double(frameLength) / sampleRate
            let signals = downsampledSignals(
                channels: channels,
                channelCount: Int(format.channelCount),
                frameLength: frameLength,
                sampleCount: configuration.fingerprintSize
            )
            rawFrames.append(
                RawFrame(
                    startTime: startTime,
                    endTime: startTime + duration,
                    fullMix: spectralFingerprint(
                        signals.fullMix,
                        duration: duration,
                        bandCount: configuration.bandCount,
                        fftSetup: fftSetup,
                        fftLog2: fftLog2
                    ),
                    stereoDifference: spectralFingerprint(
                        signals.stereoDifference,
                        duration: duration,
                        bandCount: configuration.bandCount,
                        fftSetup: fftSetup,
                        fftLog2: fftLog2
                    ),
                    fullMixRMS: rootMeanSquare(signals.fullMix),
                    stereoDifferenceRMS: rootMeanSquare(signals.stereoDifference)
                )
            )
            startTime += duration
        }

        guard rawFrames.isEmpty == false else {
            return BackgroundToneAnalysis(
                candidates: [],
                novelty: [],
                source: .fullMix,
                analyzedDuration: 0
            )
        }

        let source = preferredSource(
            rawFrames,
            channelCount: Int(format.channelCount),
            minimumRatio: configuration.minimumStereoDifferenceRatio
        )
        let fingerprints = rawFrames.map { frame in
            switch source {
            case .stereoDifference: frame.stereoDifference
            case .fullMix: frame.fullMix
            }
        }
        let noveltyValues = try noveltyCurve(
            fingerprints,
            kernelSize: configuration.kernelSize
        )
        let novelty = zip(rawFrames, noveltyValues).map { frame, strength in
            BackgroundToneNoveltySample(time: frame.startTime, strength: strength)
        }
        let candidates = selectCandidates(
            novelty: novelty,
            duration: startTime,
            configuration: configuration
        )

        return BackgroundToneAnalysis(
            candidates: candidates,
            novelty: novelty,
            source: source,
            analyzedDuration: startTime
        )
    }

    private static func sanitized(_ configuration: Configuration) -> Configuration {
        var result = configuration
        result.frameDuration = max(0.25, result.frameDuration)
        result.fingerprintSize = nearestPowerOfTwo(max(256, result.fingerprintSize))
        result.bandCount = max(4, result.bandCount)
        result.kernelSize = max(2, result.kernelSize)
        result.minimumCandidateSpacing = max(result.frameDuration, result.minimumCandidateSpacing)
        result.edgeExclusion = max(0, result.edgeExclusion)
        result.minimumNovelty = max(0, result.minimumNovelty)
        result.minimumProminence = max(0, result.minimumProminence)
        result.minimumStereoDifferenceRatio = max(0, result.minimumStereoDifferenceRatio)
        return result
    }

    private static func nearestPowerOfTwo(_ value: Int) -> Int {
        var result = 1
        while result < value { result <<= 1 }
        return result
    }

    private static func analysisError(_ description: String) -> NSError {
        NSError(
            domain: "LumeLabel.BackgroundToneAnalyzer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    // MARK: - Audio fingerprint

    private static func downsampledSignals(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameLength: Int,
        sampleCount: Int
    ) -> (fullMix: [Double], stereoDifference: [Double]) {
        if frameLength >= sampleCount {
            let decimationFactor = max(1, frameLength / sampleCount)
            let filter = [Float](
                repeating: 1 / Float(decimationFactor),
                count: decimationFactor
            )
            var left = [Float](repeating: 0, count: sampleCount)
            var right = [Float](repeating: 0, count: sampleCount)

            filter.withUnsafeBufferPointer { filterBuffer in
                left.withUnsafeMutableBufferPointer { leftBuffer in
                    vDSP_desamp(
                        channels[0],
                        vDSP_Stride(decimationFactor),
                        filterBuffer.baseAddress!,
                        leftBuffer.baseAddress!,
                        vDSP_Length(sampleCount),
                        vDSP_Length(decimationFactor)
                    )
                }
                if channelCount >= 2 {
                    right.withUnsafeMutableBufferPointer { rightBuffer in
                        vDSP_desamp(
                            channels[1],
                            vDSP_Stride(decimationFactor),
                            filterBuffer.baseAddress!,
                            rightBuffer.baseAddress!,
                            vDSP_Length(sampleCount),
                            vDSP_Length(decimationFactor)
                        )
                    }
                } else {
                    right = left
                }
            }

            var fullMix = [Double](repeating: 0, count: sampleCount)
            var stereoDifference = [Double](repeating: 0, count: sampleCount)
            let hasStereo = channelCount >= 2
            for index in 0..<sampleCount {
                let leftSample = Double(left[index])
                let rightSample = Double(right[index])
                fullMix[index] = (leftSample + rightSample) * 0.5
                stereoDifference[index] = hasStereo
                    ? (leftSample - rightSample) * 0.5
                    : 0
            }
            return (fullMix, stereoDifference)
        }

        var fullMix = [Double](repeating: 0, count: sampleCount)
        var stereoDifference = [Double](repeating: 0, count: sampleCount)
        let hasStereo = channelCount >= 2

        for outputIndex in 0..<sampleCount {
            let lower = outputIndex * frameLength / sampleCount
            let proposedUpper = (outputIndex + 1) * frameLength / sampleCount
            let upper = min(frameLength, max(lower + 1, proposedUpper))
            guard lower < frameLength else { continue }

            var mixTotal = 0.0
            var differenceTotal = 0.0
            for inputIndex in lower..<upper {
                let left = Double(channels[0][inputIndex])
                let right = hasStereo ? Double(channels[1][inputIndex]) : left
                mixTotal += (left + right) * 0.5
                differenceTotal += hasStereo ? (left - right) * 0.5 : 0
            }
            let divisor = Double(upper - lower)
            fullMix[outputIndex] = mixTotal / divisor
            stereoDifference[outputIndex] = differenceTotal / divisor
        }
        return (fullMix, stereoDifference)
    }

    private static func spectralFingerprint(
        _ samples: [Double],
        duration: TimeInterval,
        bandCount: Int,
        fftSetup: FFTSetupD,
        fftLog2: vDSP_Length
    ) -> [Double] {
        guard samples.count >= 2, duration > 0 else {
            return [Double](repeating: 0, count: bandCount)
        }

        let mean = samples.reduce(0, +) / Double(samples.count)
        var real = samples.enumerated().map { index, sample in
            let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(samples.count - 1))
            return (sample - mean) * window
        }
        var imaginary = [Double](repeating: 0, count: samples.count)
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPDoubleSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imaginaryBuffer.baseAddress!
                )
                vDSP_fft_zipD(
                    fftSetup,
                    &split,
                    1,
                    fftLog2,
                    FFTDirection(FFT_FORWARD)
                )
            }
        }

        let effectiveSampleRate = Double(samples.count) / duration
        let minimumFrequency = 20.0
        let maximumFrequency = min(650, effectiveSampleRate * 0.48)
        guard maximumFrequency > minimumFrequency else {
            return [Double](repeating: 0, count: bandCount)
        }

        let logarithmicSpan = log(maximumFrequency / minimumFrequency)
        var bands = [Double](repeating: 0, count: bandCount)
        for index in 1..<(samples.count / 2) {
            let frequency = Double(index) * effectiveSampleRate / Double(samples.count)
            guard frequency >= minimumFrequency, frequency <= maximumFrequency else { continue }
            let position = log(frequency / minimumFrequency) / logarithmicSpan
            let band = min(bandCount - 1, max(0, Int(position * Double(bandCount))))
            bands[band] += real[index] * real[index] + imaginary[index] * imaginary[index]
        }
        bands = bands.map { log1p($0) }
        return l2Normalized(bands)
    }

    private static func l2Normalized(_ values: [Double]) -> [Double] {
        let magnitude = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard magnitude > 0 else { return values.map { _ in 0 } }
        return values.map { $0 / magnitude }
    }

    private static func rootMeanSquare(_ values: [Double]) -> Double {
        guard values.isEmpty == false else { return 0 }
        return (values.reduce(0) { $0 + $1 * $1 } / Double(values.count)).squareRoot()
    }

    private static func preferredSource(
        _ frames: [RawFrame],
        channelCount: Int,
        minimumRatio: Double
    ) -> BackgroundToneAnalysis.Source {
        guard channelCount >= 2 else { return .fullMix }
        let ratios = frames.compactMap { frame -> Double? in
            guard frame.fullMixRMS > 0.000_001 else { return nil }
            return frame.stereoDifferenceRMS / frame.fullMixRMS
        }
        guard let ratio = median(ratios), ratio >= minimumRatio else { return .fullMix }
        return .stereoDifference
    }

    private static func median(_ values: [Double]) -> Double? {
        guard values.isEmpty == false else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) * 0.5
        }
        return sorted[middle]
    }

    // MARK: - Structural novelty

    private static func noveltyCurve(
        _ fingerprints: [[Double]],
        kernelSize: Int
    ) throws -> [Double] {
        guard fingerprints.isEmpty == false else { return [] }
        let half = max(1, kernelSize / 2)
        let kernel = checkerboard(half: half)
        let weight = kernel.reduce(0.0) { total, row in
            total + row.reduce(0.0) { $0 + abs($1) }
        }

        var novelty = [Double](repeating: 0, count: fingerprints.count)
        for center in fingerprints.indices {
            try Task.checkCancellation()
            var total = 0.0
            for rowOffset in -half..<half {
                let row = min(max(center + rowOffset, 0), fingerprints.count - 1)
                for columnOffset in -half..<half {
                    let column = min(max(center + columnOffset, 0), fingerprints.count - 1)
                    total += kernel[rowOffset + half][columnOffset + half]
                        * cosine(fingerprints[row], fingerprints[column])
                }
            }
            novelty[center] = max(0, total / max(weight, 1))
        }
        return novelty
    }

    private static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count else { return 0 }
        return zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func checkerboard(half: Int) -> [[Double]] {
        let sigma = max(1.0, Double(half) / 2)
        return (-half..<half).map { row in
            (-half..<half).map { column in
                let sign: Double = (row < 0) == (column < 0) ? 1 : -1
                let rowDistance = Double(row) + 0.5
                let columnDistance = Double(column) + 0.5
                return sign * exp(
                    -(rowDistance * rowDistance + columnDistance * columnDistance)
                        / (2 * sigma * sigma)
                )
            }
        }
    }

    // MARK: - Candidate selection

    private static func selectCandidates(
        novelty: [BackgroundToneNoveltySample],
        duration: TimeInterval,
        configuration: Configuration
    ) -> [BackgroundToneCandidate] {
        guard novelty.count > 2 else { return [] }
        let values = novelty.map(\.strength)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(values.count)
        let threshold = max(configuration.minimumNovelty, mean + variance.squareRoot())
        let prominenceWindow = max(
            1,
            Int(ceil(configuration.minimumCandidateSpacing / configuration.frameDuration))
        )

        var possible: [(candidate: BackgroundToneCandidate, prominence: Double)] = []
        for index in 1..<(novelty.count - 1) {
            let sample = novelty[index]
            guard sample.time >= configuration.edgeExclusion,
                  duration - sample.time >= configuration.edgeExclusion,
                  sample.strength >= threshold,
                  sample.strength >= novelty[index - 1].strength,
                  sample.strength >= novelty[index + 1].strength else {
                continue
            }
            let prominence = prominence(of: values, at: index, window: prominenceWindow)
            guard prominence >= configuration.minimumProminence else { continue }
            possible.append(
                (
                    BackgroundToneCandidate(time: sample.time, strength: sample.strength),
                    prominence
                )
            )
        }

        var accepted: [BackgroundToneCandidate] = []
        for entry in possible.sorted(by: { $0.prominence > $1.prominence }) {
            guard accepted.allSatisfy({
                abs($0.time - entry.candidate.time) >= configuration.minimumCandidateSpacing
            }) else { continue }
            accepted.append(entry.candidate)
        }
        return accepted.sorted { $0.time < $1.time }
    }

    private static func prominence(
        of values: [Double],
        at index: Int,
        window: Int
    ) -> Double {
        let lower = max(0, index - window)
        let upper = min(values.count - 1, index + window)
        guard lower < index, index < upper else { return 0 }
        let leftValley = values[lower..<index].min() ?? 0
        let rightValley = values[(index + 1)...upper].min() ?? 0
        return values[index] - max(leftValley, rightValley)
    }
}
