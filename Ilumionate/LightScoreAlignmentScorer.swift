//
//  LightScoreAlignmentScorer.swift
//  Ilumionate
//
//  Runtime quality metric for generated light scores. The score estimates how
//  closely a LightSession follows the detected trance phase timeline and
//  prosodic intent of the source audio.
//

import Foundation

struct LightScoreAlignmentReport: Codable, Sendable {
    static let productionTarget = 0.90

    let overallScore: Double
    let phaseFrequencyScore: Double
    let boundaryScore: Double
    let depthCorrelationScore: Double
    let pauseResponseScore: Double
    let structuralScore: Double

    var meetsProductionTarget: Bool {
        overallScore >= Self.productionTarget
    }
}

struct LightScoreAlignmentScorer: Sendable {

    func score(
        session: LightSession,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig = .default
    ) -> LightScoreAlignmentReport {
        let structural = structuralScore(session: session)
        let phaseFrequency = phaseFrequencyScore(session: session, analysis: analysis, config: config)
        let boundary = boundaryScore(session: session, analysis: analysis)
        let depth = depthCorrelationScore(session: session, analysis: analysis)
        let pause = pauseResponseScore(session: session, analysis: analysis)

        let overall = phaseFrequency * 0.40
            + boundary * 0.20
            + depth * 0.20
            + pause * 0.10
            + structural * 0.10

        return LightScoreAlignmentReport(
            overallScore: clamp(overall, lower: 0, upper: 1),
            phaseFrequencyScore: phaseFrequency,
            boundaryScore: boundary,
            depthCorrelationScore: depth,
            pauseResponseScore: pause,
            structuralScore: structural
        )
    }

    // MARK: - Component Scores

    private func structuralScore(session: LightSession) -> Double {
        guard !session.light_score.isEmpty, session.duration_sec > 0 else { return 0 }

        let moments = session.light_score
        var score = 1.0
        let times = moments.map(\.time)
        if times != times.sorted() { score -= 0.25 }
        if Set(times.map { Int(($0 * 1000).rounded()) }).count != times.count { score -= 0.20 }
        if moments.contains(where: { $0.time < 0 || $0.time > session.duration_sec }) { score -= 0.20 }
        if moments.contains(where: { $0.frequency < 0.5 || $0.frequency > 40.0 }) { score -= 0.20 }
        if moments.contains(where: { $0.intensity < 0.0 || $0.intensity > 1.0 }) { score -= 0.20 }

        return clamp(score, lower: 0, upper: 1)
    }

    private func phaseFrequencyScore(
        session: LightSession,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig
    ) -> Double {
        guard let phases = analysis.hypnosisMetadata?.phases, !phases.isEmpty else {
            return scoreAgainstSuggestedRange(session: session, analysis: analysis)
        }

        let samples = phases.flatMap { phaseSamples(for: $0) }
        guard !samples.isEmpty else { return 1.0 }

        let scores = samples.compactMap { sample -> Double? in
            guard let state = interpolatedMoment(at: sample.time, in: session.light_score) else { return nil }
            let target = LightScorePhaseTargeting.targetFrequency(
                phase: sample.phase.phase,
                tranceDepth: sample.phase.tranceDepthEstimate,
                progress: sample.progress,
                config: config
            )
            let tolerance = max(0.75, target * 0.16)
            let miss = abs(state.frequency - target)
            return clamp(1.0 - miss / tolerance, lower: 0, upper: 1)
        }

        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func boundaryScore(session: LightSession, analysis: AnalysisResult) -> Double {
        guard let phases = analysis.hypnosisMetadata?.phases, !phases.isEmpty else { return 1.0 }
        let moments = session.light_score
        guard !moments.isEmpty else { return 0 }

        let scores = phases.map { phase -> Double in
            let phaseDuration = max(1.0, phase.endTime - phase.startTime)
            let tolerance = min(5.0, max(1.5, phaseDuration * 0.04))
            let nearest = moments.map { abs($0.time - phase.startTime) }.min() ?? .infinity
            return clamp(1.0 - nearest / tolerance, lower: 0, upper: 1)
        }

        return scores.reduce(0, +) / Double(scores.count)
    }

    private func depthCorrelationScore(session: LightSession, analysis: AnalysisResult) -> Double {
        guard let phases = analysis.hypnosisMetadata?.phases, phases.count >= 2 else { return 1.0 }

        let pairs = phases.compactMap { phase -> (depth: Double, inverseFrequency: Double)? in
            let midpoint = (phase.startTime + phase.endTime) / 2.0
            guard let moment = interpolatedMoment(at: midpoint, in: session.light_score) else { return nil }
            return (phase.tranceDepthEstimate, -moment.frequency)
        }

        guard pairs.count >= 2 else { return 1.0 }
        let correlation = pearson(
            xs: pairs.map(\.depth),
            ys: pairs.map(\.inverseFrequency)
        )
        return clamp((correlation + 1.0) / 2.0, lower: 0, upper: 1)
    }

    private func pauseResponseScore(session: LightSession, analysis: AnalysisResult) -> Double {
        let responsivePauses = analysis.prosodicProfile?.pauses.filter { $0.category != .natural } ?? []
        guard !responsivePauses.isEmpty else { return 1.0 }

        let moments = session.light_score
        guard !moments.isEmpty else { return 0 }

        let scores = responsivePauses.map { pause -> Double in
            guard let index = moments.firstIndex(where: { abs($0.time - pause.startTime) <= 2.0 }) else {
                return 0
            }
            let current = moments[index]
            let previous = index > 0 ? moments[index - 1] : current

            switch pause.category {
            case .natural:
                return 1
            case .deliberate, .silence:
                let frequencyDrops = current.frequency <= previous.frequency + 0.05
                let intensityDrops = current.intensity <= previous.intensity + 0.02
                return (frequencyDrops ? 0.55 : 0.15) + (intensityDrops ? 0.45 : 0.10)
            case .musicOnly:
                return current.waveform == .noiseModulatedSine ? 1.0 : 0.5
            }
        }

        return scores.reduce(0, +) / Double(scores.count)
    }

    private func scoreAgainstSuggestedRange(session: LightSession, analysis: AnalysisResult) -> Double {
        guard !session.light_score.isEmpty else { return 0 }
        let range = analysis.suggestedFrequencyRange
        let moments = rangeScoringMoments(session: session, analysis: analysis)
        let scores = moments.map { moment -> Double in
            if range.contains(moment.frequency) { return 1.0 }
            let miss = moment.frequency < range.lowerBound
                ? range.lowerBound - moment.frequency
                : moment.frequency - range.upperBound
            let tolerance = max(1.0, (range.upperBound - range.lowerBound) * 0.5)
            return clamp(1.0 - miss / tolerance, lower: 0, upper: 1)
        }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func rangeScoringMoments(
        session: LightSession,
        analysis: AnalysisResult
    ) -> [LightMoment] {
        guard analysis.contentType.isHypnosisLike, session.duration_sec > 120 else {
            return session.light_score
        }

        let openingAllowance = session.duration_sec * 0.06
        let emergenceAllowance = session.duration_sec * 0.10
        let coreMoments = session.light_score.filter {
            $0.time >= openingAllowance && $0.time <= session.duration_sec - emergenceAllowance
        }

        return coreMoments.isEmpty ? session.light_score : coreMoments
    }

    // MARK: - Sampling

    private struct PhaseSample {
        let phase: PhaseSegment
        let time: TimeInterval
        let progress: Double
    }

    private func phaseSamples(for phase: PhaseSegment) -> [PhaseSample] {
        let duration = max(0, phase.endTime - phase.startTime)
        guard duration > 0 else { return [] }

        let progressValues: [Double]
        if duration >= 120 {
            progressValues = [0.0, 0.25, 0.50, 0.75, 0.92]
        } else if duration >= 45 {
            progressValues = [0.0, 0.33, 0.66, 0.92]
        } else {
            progressValues = [0.0, 0.50, 0.92]
        }

        return progressValues.map { progress in
            PhaseSample(
                phase: phase,
                time: phase.startTime + duration * progress,
                progress: progress
            )
        }
    }

    private func interpolatedMoment(
        at time: TimeInterval,
        in moments: [LightMoment]
    ) -> LightMoment? {
        let ordered = moments.sorted { $0.time < $1.time }
        guard !ordered.isEmpty else { return nil }
        guard time > ordered[0].time else { return ordered[0] }
        guard time < ordered[ordered.count - 1].time else { return ordered.last }

        for index in 1..<ordered.count where ordered[index].time >= time {
            let previous = ordered[index - 1]
            let next = ordered[index]
            let span = max(next.time - previous.time, 0.001)
            let alpha = clamp((time - previous.time) / span, lower: 0, upper: 1)
            return LightMoment(
                time: time,
                frequency: previous.frequency + (next.frequency - previous.frequency) * alpha,
                intensity: previous.intensity + (next.intensity - previous.intensity) * alpha,
                waveform: previous.waveform,
                ramp_duration: next.ramp_duration,
                bilateral: previous.bilateral,
                bilateral_transition_duration: next.bilateral_transition_duration,
                color_temperature: next.color_temperature ?? previous.color_temperature
            )
        }

        return ordered.last
    }

    private func pearson(xs: [Double], ys: [Double]) -> Double {
        guard xs.count == ys.count, xs.count >= 2 else { return 0 }
        let xMean = xs.reduce(0, +) / Double(xs.count)
        let yMean = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0
        var xDenominator = 0.0
        var yDenominator = 0.0

        for index in xs.indices {
            let x = xs[index] - xMean
            let y = ys[index] - yMean
            numerator += x * y
            xDenominator += x * x
            yDenominator += y * y
        }

        let denominator = (xDenominator * yDenominator).squareRoot()
        guard denominator > 0 else { return 1.0 }
        return numerator / denominator
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
