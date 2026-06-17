//  CorpusReport.swift
//  CorpusGenKit
//
//  Summarizes labeled corpus coverage so the training set can be checked after
//  importing real labels or generating synthetic batches.
//
import Foundation
import CorpusKit

public struct CorpusReport: Sendable, Equatable {
    public struct SourceSummary: Sendable, Equatable {
        public let source: CorpusSource
        public let caseCount: Int
        public let labeledCaseCount: Int
        public let labeledSeconds: Int
    }

    public struct PhaseSummary: Sendable, Equatable {
        public let phase: TrancePhase
        public let labeledSeconds: Int
        public let caseCount: Int
    }

    public let caseCount: Int
    public let labeledCaseCount: Int
    public let labeledSeconds: Int
    public let sources: [SourceSummary]
    public let phases: [PhaseSummary]
    public let issues: [String]

    public static let defaultSparsePhaseThreshold = 120

    public static func make(
        cases: [CorpusCase],
        sparsePhaseThreshold: Int = defaultSparsePhaseThreshold
    ) -> CorpusReport {
        var sourceStats: [CorpusSource: (cases: Int, labeledCases: Int, seconds: Int)] = [:]
        var phaseSeconds: [TrancePhase: Int] = [:]
        var phaseCaseIDs: [TrancePhase: Set<String>] = [:]
        var issues: [String] = []

        for kase in cases {
            var stats = sourceStats[kase.source] ?? (cases: 0, labeledCases: 0, seconds: 0)
            stats.cases += 1

            if kase.truth.isEmpty {
                issues.append("\(kase.id) has no truth spans")
            } else {
                stats.labeledCases += 1
            }

            if kase.segments.isEmpty {
                issues.append("\(kase.id) has no transcript segments")
            }

            issues.append(contentsOf: validateTruth(in: kase))

            let seconds = labeledSecondsByPhase(in: kase)
            for (phase, count) in seconds {
                phaseSeconds[phase, default: 0] += count
                if count > 0 {
                    phaseCaseIDs[phase, default: []].insert(kase.id)
                    stats.seconds += count
                }
            }

            sourceStats[kase.source] = stats
        }

        let sourceOrder: [CorpusSource] = [.real, .synthetic]
        let sources = sourceOrder.compactMap { source -> SourceSummary? in
            guard let stats = sourceStats[source] else { return nil }
            return SourceSummary(
                source: source,
                caseCount: stats.cases,
                labeledCaseCount: stats.labeledCases,
                labeledSeconds: stats.seconds
            )
        }

        let phaseOrder = TrancePhase.orderedHypnosisPhases + [.transitional]
        let phases = phaseOrder.map { phase in
            PhaseSummary(
                phase: phase,
                labeledSeconds: phaseSeconds[phase] ?? 0,
                caseCount: phaseCaseIDs[phase]?.count ?? 0
            )
        }

        for phase in TrancePhase.orderedHypnosisPhases {
            let seconds = phaseSeconds[phase] ?? 0
            if seconds == 0 {
                issues.append("missing labels for \(phase.rawValue)")
            } else if seconds < sparsePhaseThreshold {
                issues.append("sparse labels for \(phase.rawValue): \(seconds)s")
            }
        }

        return CorpusReport(
            caseCount: cases.count,
            labeledCaseCount: cases.filter { !$0.truth.isEmpty }.count,
            labeledSeconds: phaseSeconds.values.reduce(0, +),
            sources: sources,
            phases: phases,
            issues: issues.sorted()
        )
    }

    public var text: String {
        var lines: [String] = [
            "Corpus report",
            "Cases: \(caseCount) (\(labeledCaseCount) labeled)",
            "Labeled seconds: \(labeledSeconds)",
            "",
            "By source:",
        ]

        if sources.isEmpty {
            lines.append("  none")
        } else {
            for source in sources {
                lines.append(
                    "  \(source.source.rawValue): \(source.caseCount) cases, "
                    + "\(source.labeledCaseCount) labeled, "
                    + "\(source.labeledSeconds)s labeled"
                )
            }
        }

        lines.append("")
        lines.append("By phase:")
        for phase in phases where phase.labeledSeconds > 0 {
            lines.append("  \(phase.phase.rawValue): \(phase.labeledSeconds)s across \(phase.caseCount) cases")
        }
        if !phases.contains(where: { $0.labeledSeconds > 0 }) {
            lines.append("  none")
        }

        lines.append("")
        lines.append("Issues:")
        if issues.isEmpty {
            lines.append("  none")
        } else {
            lines.append(contentsOf: issues.map { "  - \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private static func labeledSecondsByPhase(in kase: CorpusCase) -> [TrancePhase: Int] {
        guard !kase.truth.isEmpty else { return [:] }
        let bucketCount = max(0, Int(ceil(kase.duration)))
        guard bucketCount > 0 else { return [:] }

        var counts: [TrancePhase: Int] = [:]
        for second in 0..<bucketCount {
            guard let phase = phase(at: Double(second) + 0.5, in: kase.truth) else { continue }
            counts[phase, default: 0] += 1
        }
        return counts
    }

    private static func phase(at time: TimeInterval, in spans: [PhaseTruthSpan]) -> TrancePhase? {
        for span in spans where time >= span.start && time < span.end {
            return span.phase.labelingPhase
        }
        return nil
    }

    private static func validateTruth(in kase: CorpusCase) -> [String] {
        let sorted = kase.truth.sorted { $0.start < $1.start }
        var issues: [String] = []

        for span in sorted {
            if span.end <= span.start {
                issues.append("\(kase.id) has non-positive \(span.phase.rawValue) truth span")
            }
            if span.start < 0 || span.end > kase.duration + 0.001 {
                issues.append("\(kase.id) has \(span.phase.rawValue) truth span outside duration")
            }
        }

        for pair in zip(sorted, sorted.dropFirst()) where pair.1.start < pair.0.end {
            issues.append(
                "\(kase.id) has overlapping truth spans "
                + "\(pair.0.phase.rawValue) and \(pair.1.phase.rawValue)"
            )
        }

        return issues
    }
}
