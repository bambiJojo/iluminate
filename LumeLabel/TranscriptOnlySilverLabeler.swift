//
//  TranscriptOnlySilverLabeler.swift
//  LumeLabel
//
//  Conservatively fuses transcript classification, semantic catalog intent,
//  and background-tone changes. Output is always explicitly derived silver.
//

import Foundation

nonisolated enum TranscriptOnlySilverLabeler {
    struct SemanticSignal: Sendable, Equatable {
        let phase: TrancePhase
        let startTime: TimeInterval
        let endTime: TimeInterval
        let confidence: Double
    }

    struct Proposal: Sendable {
        let phases: [LabeledFile.LabeledPhase]
        let confidence: Double
        let semanticAgreement: Double
        let toneAlignedBoundaryCount: Int
        let catalogExampleCount: Int

        enum ApplicationError: LocalizedError {
            case notSafetyScoped
            case wouldOverwriteHumanLabels

            var errorDescription: String? {
                switch self {
                case .notSafetyScoped:
                    return "Transcript-only Bambi labels can only be applied to safety-scoped files."
                case .wouldOverwriteHumanLabels:
                    return "Existing human labels were preserved."
                }
            }
        }

        func applying(to file: LabeledFile, now: Date = Date()) throws -> LabeledFile {
            guard BambiSafetyPolicy.requiresTranscriptOnlyLabeling(file) else {
                throw ApplicationError.notSafetyScoped
            }
            guard file.phases.isEmpty || BambiSafetyPolicy.isTranscriptOnlySilver(file) else {
                throw ApplicationError.wouldOverwriteHumanLabels
            }

            var derived = file
            derived.phases = phases
            derived.labeledAt = now
            let confidencePercent = Int((confidence * 100).rounded())
            let agreementPercent = Int((semanticAgreement * 100).rounded())
            derived.labelerNotes = "\(BambiSafetyPolicy.silverLabelPrefix); not human reviewed. Pipeline: timestamped transcript + keyword phases + bundled catalog intents + background-tone boundary alignment. Confidence \(confidencePercent)%; model agreement \(agreementPercent)%; \(toneAlignedBoundaryCount) tone-aligned boundaries; \(catalogExampleCount) catalog examples. Independent review required before promotion to gold."
            return try derived.validatedForPersistence()
        }
    }

    static func makeProposal(
        duration: TimeInterval,
        keywordSegments: [PhaseSegment],
        semanticSignals: [SemanticSignal],
        toneCandidates: [BackgroundToneCandidate],
        transcriptConfidence: Double,
        catalogExampleCount: Int
    ) -> Proposal? {
        guard duration.isFinite, duration > 0 else { return nil }

        var runs = canonicalRuns(from: keywordSegments, duration: duration)
        guard runs.isEmpty == false else { return nil }
        let alignedBoundaryCount = alignBoundaries(
            in: &runs,
            duration: duration,
            candidates: toneCandidates
        )
        let agreement = semanticAgreement(for: runs, signals: semanticSignals)
        let boundedTranscriptConfidence = min(max(transcriptConfidence, 0), 1)
        let catalogSupport = catalogExampleCount > 0 ? 1.0 : 0.0
        let toneSupport = runs.count > 1
            ? Double(alignedBoundaryCount) / Double(runs.count - 1)
            : 0
        let confidence = min(max(
            0.30
                + (boundedTranscriptConfidence * 0.20)
                + (agreement * 0.30)
                + (catalogSupport * 0.10)
                + (toneSupport * 0.10),
            0
        ), 0.90)

        let phases = runs.map { run in
            let runAgreement = semanticAgreement(for: [run], signals: semanticSignals)
            let agreementPercent = Int((runAgreement * 100).rounded())
            return LabeledFile.LabeledPhase(
                phase: run.phase,
                startTime: run.startTime,
                endTime: run.endTime,
                notes: "Derived silver: transcript classification + catalog intent; semantic agreement \(agreementPercent)%."
            )
        }
        return Proposal(
            phases: phases,
            confidence: confidence,
            semanticAgreement: agreement,
            toneAlignedBoundaryCount: alignedBoundaryCount,
            catalogExampleCount: catalogExampleCount
        )
    }

    private struct Run {
        var phase: TrancePhase
        var startTime: TimeInterval
        var endTime: TimeInterval
    }

    private static func canonicalRuns(
        from segments: [PhaseSegment],
        duration: TimeInterval
    ) -> [Run] {
        let sorted = segments
            .filter { $0.startTime.isFinite && $0.endTime.isFinite && $0.endTime > $0.startTime }
            .sorted {
                if $0.startTime == $1.startTime { return $0.endTime < $1.endTime }
                return $0.startTime < $1.startTime
            }
        guard sorted.isEmpty == false else { return [] }

        var boundaries = [TimeInterval(0)]
        boundaries.append(contentsOf: sorted.dropFirst().map {
            min(max($0.startTime, 0), duration)
        })
        boundaries.append(duration)

        var runs: [Run] = []
        for index in sorted.indices {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end > start else { continue }
            let phase = sorted[index].phase.labelingPhase
            if let last = runs.last, last.phase == phase {
                runs[runs.count - 1].endTime = end
            } else {
                runs.append(Run(phase: phase, startTime: start, endTime: end))
            }
        }
        if runs.isEmpty == false {
            runs[0].startTime = 0
            runs[runs.count - 1].endTime = duration
        }
        return runs
    }

    private static func alignBoundaries(
        in runs: inout [Run],
        duration: TimeInterval,
        candidates: [BackgroundToneCandidate]
    ) -> Int {
        guard runs.count > 1 else { return 0 }
        let tolerance = max(15, min(45, duration * 0.025))
        let minimumRunDuration = max(5, min(30, duration * 0.005))
        var usedCandidateTimes = Set<TimeInterval>()
        var aligned = 0

        for index in 1..<runs.count {
            let original = runs[index].startTime
            let lower = runs[index - 1].startTime + minimumRunDuration
            let upper = runs[index].endTime - minimumRunDuration
            guard lower < upper else { continue }
            let candidate = candidates
                .filter {
                    $0.strength >= 0.15
                        && abs($0.time - original) <= tolerance
                        && $0.time >= lower
                        && $0.time <= upper
                        && usedCandidateTimes.contains($0.time) == false
                }
                .min {
                    let lhsDistance = abs($0.time - original)
                    let rhsDistance = abs($1.time - original)
                    return lhsDistance == rhsDistance ? $0.strength > $1.strength : lhsDistance < rhsDistance
                }
            guard let candidate else { continue }
            runs[index - 1].endTime = candidate.time
            runs[index].startTime = candidate.time
            usedCandidateTimes.insert(candidate.time)
            aligned += 1
        }
        return aligned
    }

    private static func semanticAgreement(
        for runs: [Run],
        signals: [SemanticSignal]
    ) -> Double {
        guard runs.isEmpty == false, signals.isEmpty == false else { return 0 }
        var matchingWeight = 0.0
        var totalWeight = 0.0
        for run in runs {
            for signal in signals {
                let overlap = max(0, min(run.endTime, signal.endTime) - max(run.startTime, signal.startTime))
                guard overlap > 0 else { continue }
                let weight = overlap * min(max(signal.confidence, 0), 1)
                totalWeight += weight
                if run.phase == signal.phase.labelingPhase {
                    matchingWeight += weight
                }
            }
        }
        return totalWeight > 0 ? matchingWeight / totalWeight : 0
    }
}
