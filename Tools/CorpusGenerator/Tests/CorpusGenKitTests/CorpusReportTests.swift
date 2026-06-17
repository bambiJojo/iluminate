import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct CorpusReportTests {

    private func makeCase(
        id: String = "case-1",
        source: CorpusSource = .real,
        duration: TimeInterval = 10,
        segments: [CorpusSegment] = [CorpusSegment(text: "relax", timestamp: 0, duration: 10, confidence: 1)],
        truth: [PhaseTruthSpan]
    ) -> CorpusCase {
        CorpusCase(
            id: id,
            source: source,
            boundaryMode: .exact,
            ambiguityLevel: .low,
            duration: duration,
            segments: segments,
            truth: truth
        )
    }

    @Test("Counts labeled seconds by second midpoint")
    func countsLabeledSecondsByMidpoint() {
        let kase = makeCase(
            duration: 4,
            truth: [
                PhaseTruthSpan(phase: .induction, start: 0, end: 2),
                PhaseTruthSpan(phase: .deepening, start: 2, end: 3),
            ]
        )

        let report = CorpusReport.make(cases: [kase], sparsePhaseThreshold: 1)

        #expect(report.caseCount == 1)
        #expect(report.labeledCaseCount == 1)
        #expect(report.labeledSeconds == 3)
        #expect(report.sources.first?.source == .real)
        #expect(report.sources.first?.labeledSeconds == 3)
        #expect(report.phases.first { $0.phase == .induction }?.labeledSeconds == 2)
        #expect(report.phases.first { $0.phase == .deepening }?.labeledSeconds == 1)
    }

    @Test("Reports sparse, missing, transcript, and truth-span issues")
    func reportsIssues() {
        let kase = makeCase(
            id: "bad-case",
            duration: 5,
            segments: [],
            truth: [
                PhaseTruthSpan(phase: .induction, start: 0, end: 2),
                PhaseTruthSpan(phase: .deepening, start: 1, end: 4),
                PhaseTruthSpan(phase: .emergence, start: 4, end: 8),
            ]
        )

        let report = CorpusReport.make(cases: [kase], sparsePhaseThreshold: 3)

        #expect(report.issues.contains("bad-case has no transcript segments"))
        #expect(report.issues.contains("bad-case has overlapping truth spans induction and deepening"))
        #expect(report.issues.contains("bad-case has emergence truth span outside duration"))
        #expect(report.issues.contains("sparse labels for induction: 2s"))
        #expect(report.issues.contains("missing labels for suggestions"))
    }

    @Test("Legacy content phases count as suggestions")
    func legacyContentPhasesCountAsSuggestions() {
        let kase = makeCase(
            duration: 3,
            truth: [PhaseTruthSpan(phase: .therapy, start: 0, end: 3)]
        )

        let report = CorpusReport.make(cases: [kase], sparsePhaseThreshold: 1)

        #expect(report.phases.first { $0.phase == .suggestions }?.labeledSeconds == 3)
        #expect(report.phases.first { $0.phase == .therapy } == nil)
    }

    @Test("Text report includes source, phase, and issue sections")
    func textReport() {
        let kase = makeCase(
            source: .synthetic,
            truth: [PhaseTruthSpan(phase: .suggestions, start: 0, end: 10)]
        )

        let text = CorpusReport.make(cases: [kase], sparsePhaseThreshold: 1).text

        #expect(text.contains("Corpus report"))
        #expect(text.contains("synthetic: 1 cases, 1 labeled, 10s labeled"))
        #expect(text.contains("suggestions: 10s across 1 cases"))
        #expect(text.contains("Issues:"))
    }
}
