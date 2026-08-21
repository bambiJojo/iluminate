//
//  LightImpactOfBoundariesTests.swift
//  IlumionateTests
//
//  F1 is a proxy. The product question is whether wrongly-placed boundaries
//  produce materially different light, and it is answerable directly: generate a
//  session from each segmentation and compare the trajectories.
//
//  Every segmentation is given the *best possible* labelling — the phase the
//  labeller says is active at each segment's midpoint — so the only variable is
//  where the boundaries fall. Mislabelling is a separate question.
//
//  Measured 2026-08-19, frequency deviation as a share of the generator's 8.8 Hz
//  range:
//
//                        BF    DFTC   Mind Melt   Tick Tock   mean
//      detector           4%     4%       4%          4%       4.0%   perfect labels
//      AS SHIPPED        28%    18%       8%         32%      21.5%
//      END-TO-END         8%    11%      17%         19%      13.8%   no truth at all
//      TEMPLATE          15%     11%      15%         13%      13.5%   no detection at all
//
//  THE TEMPLATE MATCHES THE PIPELINE. A fixed positional arc — induction to 15%,
//  deepening to 60%, suggestions to 85%, conditioning to 96%, emergence after —
//  using no audio, no transcript and no detection, scores 13.5% against the
//  pipeline's 13.8%, and is more consistent doing it (11-15% against 8-19%).
//
//  Per file the pipeline is -7, 0, +2, +6 against the template: it wins on BF
//  and loses on Tick Tock. Mean difference +0.25 points, in the template's
//  favour.
//
//  This is consistent with the feature correlations. Against the 32 labelled
//  segments with prosody, trance depth correlates r = +0.09 with speech rate,
//  -0.01 with pitch, +0.01 with volume, +0.38 with speech/silence ratio — and
//  +0.40 with position in the file. Lexical markers do no better: +0.14 for
//  deepening words, -0.23 for awakening words. Position is the strongest signal
//  anyone has measured here, and a template is position used directly.
//
//  Measured again after the seven-phase target and a namer that emits
//  conditioning. AS SHIPPED improved on its own — 21.5% to 19.8% — because the
//  incumbent also stops folding conditioning into suggestions. Adding
//  conditioning to the namer was a wash on this sample: BF gained two points,
//  Mind Melt and Tick Tock each lost one, mean unchanged at 13.8%.
//
//  (END-TO-END was 14/15/20/18, mean 16.8%, before the emergence priors were
//  corrected against the corpus — see SegmentPhaseNamer.)
//
//  Against the improved baseline the per-file differences are -20, -10, +10, -4:
//  a mean of -6.0 points, 95% interval -18.3 to +6.3. STILL NOT ESTABLISHED, and
//  four files cannot settle it. Mind Melt remains the only regression and is now
//  the only file where the incumbent is better.
//
//  Two things it does establish. Boundaries are nearly free once labels are
//  right — feeding the detector prosody took it to a flat 4% while *raising* its
//  boundary count to 10-21 against a labelled 6-11. And naming carries the whole
//  remaining gap: 4% with correct labels against 16.8% with the namer.
//
//  Mind Melt hints at why. It draws the most segments (18) and is the only
//  regression, which points at over-segmentation hurting indirectly — every
//  extra segment is another chance to select a wrong behaviour. Merging was
//  worthless for boundary F1, but reducing the number of naming decisions is a
//  different objective and is unmeasured.
//
//  Runs only when TEST_RUNNER_LUMESYNC_CORPUS points at a LumeLabel corpus.
//  Reports through a Swift Testing attachment; see IncumbentBaselineTests for
//  why neither stdout nor a file works from the sandboxed test host.
//

import Testing
import Foundation
import CorpusKit
@testable import Ilumionate

private func corpusRoot() -> URL? {
    let environment = ProcessInfo.processInfo.environment
    let path = environment["LUMESYNC_CORPUS"] ?? environment["TEST_RUNNER_LUMESYNC_CORPUS"]
    return path.map { URL(filePath: $0) }
}

private struct LabelledPhase {
    let phase: TrancePhase
    let startTime: TimeInterval
    let endTime: TimeInterval
}

private struct Subject {
    let name: String
    let duration: TimeInterval
    let phases: [LabelledPhase]
    let segments: [AudioTranscriptionSegment]
    let words: [WordTimestamp]
    let prosody: ProsodicProfile?
}

private func stripControlTokens(_ text: String) -> String {
    text.components(separatedBy: .whitespacesAndNewlines)
        .filter { $0.isEmpty == false && $0.contains("<|") == false }
        .joined(separator: " ")
}

private func loadProsody() -> [String: ProsodicProfile] {
    let environment = ProcessInfo.processInfo.environment
    guard let path = environment["LUMESYNC_PROSODY"] ?? environment["TEST_RUNNER_LUMESYNC_PROSODY"] else {
        return [:]
    }
    var profiles: [String: ProsodicProfile] = [:]
    for file in (try? FileManager.default.contentsOfDirectory(
        at: URL(filePath: path), includingPropertiesForKeys: nil
    )) ?? [] {
        guard file.pathExtension == "json",
              let data = try? Data(contentsOf: file),
              let profile = try? JSONDecoder().decode(ProsodicProfile.self, from: data) else { continue }
        profiles[file.deletingPathExtension().lastPathComponent] = profile
    }
    return profiles
}

private func loadSubjects(from root: URL) -> [Subject] {
    let manager = FileManager.default
    let prosodyBySHA = loadProsody()
    var segmentsBySHA: [String: [AudioTranscriptionSegment]] = [:]

    for file in (try? manager.contentsOfDirectory(
        at: root.appending(path: "AnalyzerDataset/cache/transcripts"),
        includingPropertiesForKeys: nil
    )) ?? [] {
        guard file.pathExtension == "json",
              let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = object["audioSHA256"] as? String,
              let transcription = object["transcription"] as? [String: Any],
              let raw = transcription["segments"] as? [[String: Any]] else { continue }

        segmentsBySHA[sha] = raw.compactMap { segment in
            guard let text = segment["text"] as? String,
                  let timestamp = segment["timestamp"] as? Double,
                  let duration = segment["duration"] as? Double else { return nil }
            let cleaned = stripControlTokens(text)
            guard cleaned.isEmpty == false else { return nil }
            return AudioTranscriptionSegment(
                text: cleaned, timestamp: timestamp, duration: duration, confidence: 0
            )
        }
    }

    var subjects: [Subject] = []
    for file in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
        guard file.pathExtension == "json",
              let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = object["audioSHA256"] as? String,
              let rawPhases = object["phases"] as? [[String: Any]],
              rawPhases.count > 1,
              let segments = segmentsBySHA[sha], segments.isEmpty == false else { continue }

        let phases = rawPhases.compactMap { entry -> LabelledPhase? in
            guard let raw = entry["phase"] as? String,
                  let phase = TrancePhase(rawValue: raw),
                  let start = entry["startTime"] as? Double,
                  let end = entry["endTime"] as? Double else { return nil }
            return LabelledPhase(phase: phase, startTime: start, endTime: end)
        }.sorted { $0.startTime < $1.startTime }
        guard phases.count > 1 else { continue }

        subjects.append(
            Subject(
                name: (object["audioFilename"] as? String) ?? sha,
                duration: (object["audioDuration"] as? Double) ?? 0,
                phases: phases,
                segments: segments,
                words: HypnosisPhaseAnalyzer.approximateWordTimestamps(from: segments),
                prosody: prosodyBySHA[sha]
            )
        )
    }
    return subjects.sorted { $0.name < $1.name }
}

/// The label the corpus assigns at a given moment.
private func phase(at time: TimeInterval, in phases: [LabelledPhase]) -> TrancePhase {
    phases.last { $0.startTime <= time }?.phase ?? phases.first?.phase ?? .induction
}

/// Builds an analysis whose phases have the given boundaries, each labelled with
/// the truth at its midpoint — the best labelling that segmentation could get.
private func analysis(
    boundaries: [TimeInterval],
    truth: [LabelledPhase],
    duration: TimeInterval
) -> AnalysisResult {
    let starts = ([0] + boundaries).sorted()
    let segments = starts.enumerated().map { index, start -> PhaseSegment in
        let end = index + 1 < starts.count ? starts[index + 1] : duration
        let midpoint = start + (end - start) / 2
        let assigned = phase(at: midpoint, in: truth)
        return PhaseSegment(
            phase: assigned,
            startTime: start,
            endTime: end,
            characteristics: assigned.displayName,
            tranceDepthEstimate: assigned.tranceDepthEstimate
        )
    }
    let metadata = HypnosisMetadata(
        phases: segments,
        inductionStyle: .permissive,
        estimatedTranceDeph: .medium,
        suggestionDensity: 0.5,
        languagePatterns: [],
        detectedTechniques: []
    )
    return AnalysisFixtures.hypnosisAnalysis.with(hypnosisMetadata: metadata)
}

/// Samples a generated session at a fixed cadence. Control points are sparse and
/// time-ordered, so linear interpolation between them models what a player does
/// closely enough to compare two sessions against each other.
private func sample(
    _ session: LightSession,
    duration: TimeInterval,
    interval: TimeInterval = 1
) -> (frequency: [Double], intensity: [Double]) {
    let moments = session.light_score.sorted { $0.time < $1.time }
    guard moments.isEmpty == false else { return ([], []) }

    var frequency: [Double] = []
    var intensity: [Double] = []
    var index = 0
    var time = 0.0
    while time <= duration {
        while index + 1 < moments.count, moments[index + 1].time <= time { index += 1 }
        let current = moments[index]
        if index + 1 < moments.count {
            let next = moments[index + 1]
            let span = next.time - current.time
            let ratio = span > 0 ? (time - current.time) / span : 0
            frequency.append(current.frequency + (next.frequency - current.frequency) * ratio)
            intensity.append(current.intensity + (next.intensity - current.intensity) * ratio)
        } else {
            frequency.append(current.frequency)
            intensity.append(current.intensity)
        }
        time += interval
    }
    return (frequency, intensity)
}

private func meanAbsoluteDifference(_ lhs: [Double], _ rhs: [Double]) -> Double {
    let count = min(lhs.count, rhs.count)
    guard count > 0 else { return 0 }
    return zip(lhs.prefix(count), rhs.prefix(count))
        .reduce(0.0) { $0 + abs($1.0 - $1.1) } / Double(count)
}

/// Which of `intensityContour`'s four behaviours a phase selects. Two phases in
/// the same group produce identical light, so a naming mismatch between them
/// costs nothing — only a mismatch across groups moves the output.
private func lightBehaviour(_ phase: TrancePhase) -> String {
    switch phase.labelingPhaseForLight {
    case .emergence: return "RISE"
    case .fractionation: return "FAST-OSC"
    case .suggestions: return "OSC"
    default: return "DECAY"
    }
}

private extension TrancePhase {
    /// Groups exactly as `SessionGenerator.intensityContour` switches.
    var labelingPhaseForLight: TrancePhase {
        switch self {
        case .preTalk, .induction, .deepening, .confusion: return .induction
        case .therapy, .suggestions, .eroticSuggestions, .conditioning, .brainwashing: return .suggestions
        case .fractionation: return .fractionation
        case .emergence: return .emergence
        case .transitional: return .transitional
        }
    }
}

struct LightImpactOfBoundariesTests {

    /// Per-segment detail for one file, to find *which* naming decision costs
    /// the light rather than guessing from an aggregate.
    @Test(
        "Diagnose naming decisions segment by segment",
        .enabled(if: corpusRoot() != nil)
    )
    func diagnoseNaming() throws {
        let root = try #require(corpusRoot())
        let subjects = loadSubjects(from: root)
        try #require(subjects.isEmpty == false)

        var lines: [String] = []
        for subject in subjects {
            let detected = StructuralSegmenter.segment(
                words: subject.words,
                prosody: subject.prosody,
                duration: subject.duration,
                minimumSegmentDuration: 60,
                minimumNovelty: 0.15
            )
            let names = SegmentPhaseNamer.name(
                segments: detected.segments,
                countingRuns: detected.countingRuns,
                prosody: subject.prosody,
                duration: subject.duration
            )

            var mismatched = 0
            var mismatchedSeconds = 0.0
            lines.append("")
            lines.append("=== \(subject.name) — \(detected.segments.count) segments, \(detected.countingRuns.count) counting run(s)")
            lines.append("    counts: " + detected.countingRuns.map {
                "\($0.direction == .descending ? "↓" : "↑")\(Int($0.startTime))s"
            }.joined(separator: " "))
            for (segment, predicted) in zip(detected.segments, names) {
                let midpoint = segment.startTime + (segment.endTime - segment.startTime) / 2
                let actual = phase(at: midpoint, in: subject.phases)
                let predictedLight = lightBehaviour(predicted)
                let actualLight = lightBehaviour(actual)
                let flag = predictedLight == actualLight ? "   " : " ✗ "
                if predictedLight != actualLight {
                    mismatched += 1
                    mismatchedSeconds += segment.endTime - segment.startTime
                }
                lines.append(
                    "\(flag)\(Int(segment.startTime))-\(Int(segment.endTime))s  "
                        + "predicted \(predicted.rawValue) [\(predictedLight)]  "
                        + "labelled \(actual.rawValue) [\(actualLight)]"
                )
            }
            let share = subject.duration > 0 ? mismatchedSeconds / subject.duration * 100 : 0
            lines.append(
                "    → \(mismatched) of \(names.count) segments in the wrong light behaviour, "
                    + "\(Int(share))% of the file's duration"
            )
        }

        Attachment.record(lines.joined(separator: "\n"), named: "naming-diagnosis.txt")
        #expect(subjects.isEmpty == false)
    }

    @Test(
        "Compare generated light from detector and incumbent boundaries against truth",
        .enabled(if: corpusRoot() != nil)
    )
    func boundaryErrorMeasuredInLight() throws {
        let root = try #require(corpusRoot())
        let subjects = loadSubjects(from: root)
        try #require(subjects.isEmpty == false)

        let generator = SessionGenerator()
        let keyword = HypnosisPhaseAnalyzer()
        var lines = [
            "Light impact of boundary error — mean absolute difference from the",
            "session generated by the labeller's own boundaries.",
            "",
            "Every segmentation is labelled with the truth at each segment's",
            "midpoint, so only boundary placement varies.",
            ""
        ]

        for subject in subjects {
            let audioFile = AudioFile(
                filename: subject.name,
                duration: subject.duration,
                fileSize: 0,
                createdDate: Date(timeIntervalSince1970: 0)
            )

            let truthBoundaries = Array(subject.phases.map(\.startTime).dropFirst())
            let detected = StructuralSegmenter.segment(
                words: subject.words,
                prosody: subject.prosody,
                duration: subject.duration,
                minimumSegmentDuration: 60,
                minimumNovelty: 0.15
            )
            let detectorBoundaries = Array(detected.segments.map(\.startTime).dropFirst())
            let incumbentBoundaries = Array(
                keyword.analyze(segments: subject.segments, duration: subject.duration)
                    .map(\.startTime).sorted().dropFirst()
            )

            func session(_ boundaries: [TimeInterval]) -> LightSession {
                generator.generateSession(
                    from: audioFile,
                    analysis: analysis(
                        boundaries: boundaries,
                        truth: subject.phases,
                        duration: subject.duration
                    )
                )
            }

            // What the shipping pipeline actually delivers: its own boundaries
            // *and* its own labels. The comparisons above hand every
            // segmentation the correct labels to isolate boundary error; this
            // one does not, because a wrong label selects a different light
            // behaviour entirely — decay, oscillation, or rise.
            let incumbentPhases = keyword.analyze(segments: subject.segments, duration: subject.duration)
            let asShipped = generator.generateSession(
                from: audioFile,
                analysis: AnalysisFixtures.hypnosisAnalysis.with(
                    hypnosisMetadata: HypnosisMetadata(
                        phases: incumbentPhases,
                        inductionStyle: .permissive,
                        estimatedTranceDeph: .medium,
                        suggestionDensity: 0.5,
                        languagePatterns: [],
                        detectedTechniques: []
                    )
                )
            )

            // The full replacement pipeline, using no truth at all: detected
            // boundaries, named by SegmentPhaseNamer. This is the row that has to
            // beat AS SHIPPED for any of the work to be worth landing.
            let namedPhases = SegmentPhaseNamer.name(
                segments: detected.segments,
                countingRuns: detected.countingRuns,
                prosody: subject.prosody,
                duration: subject.duration
            )
            let namedSegments = zip(detected.segments, namedPhases).map { segment, phase in
                PhaseSegment(
                    phase: phase,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    characteristics: phase.displayName,
                    tranceDepthEstimate: phase.tranceDepthEstimate
                )
            }
            let endToEnd = generator.generateSession(
                from: audioFile,
                analysis: AnalysisFixtures.hypnosisAnalysis.with(
                    hypnosisMetadata: HypnosisMetadata(
                        phases: namedSegments,
                        inductionStyle: .permissive,
                        estimatedTranceDeph: .medium,
                        suggestionDensity: 0.5,
                        languagePatterns: [],
                        detectedTechniques: []
                    )
                )
            )

            // Merge before naming. Merging was worthless for boundary F1, but the
            // objective here is different: fewer segments means fewer chances to
            // select a wrong light behaviour, and naming carries most of the
            // remaining error.
            func mergedThenNamed(cliff: Double) -> (session: LightSession, count: Int) {
                let merged = StructuralMerger.merge(detected, minimumCliff: cliff)
                let phases = SegmentPhaseNamer.name(
                    segments: merged.segments,
                    countingRuns: merged.countingRuns,
                    prosody: subject.prosody,
                    duration: subject.duration
                )
                let segments = zip(merged.segments, phases).map { segment, phase in
                    PhaseSegment(
                        phase: phase,
                        startTime: segment.startTime,
                        endTime: segment.endTime,
                        characteristics: phase.displayName,
                        tranceDepthEstimate: phase.tranceDepthEstimate
                    )
                }
                return (
                    generator.generateSession(
                        from: audioFile,
                        analysis: AnalysisFixtures.hypnosisAnalysis.with(
                            hypnosisMetadata: HypnosisMetadata(
                                phases: segments,
                                inductionStyle: .permissive,
                                estimatedTranceDeph: .medium,
                                suggestionDensity: 0.5,
                                languagePatterns: [],
                                detectedTechniques: []
                            )
                        )
                    ),
                    segments.count
                )
            }

            // The control this whole branch needs: a fixed positional template,
            // using no detection and no evidence at all. Trance depth's strongest
            // measured predictor is position in the file (r = 0.40, against
            // r ≈ 0.0 for speech rate, pitch and volume and r ≈ 0.2 for lexical
            // markers), so if the detector and namer cannot beat a template they
            // are not earning their complexity.
            let templateSpans: [(TrancePhase, Double, Double)] = [
                (.induction, 0.00, 0.15),
                (.deepening, 0.15, 0.60),
                (.suggestions, 0.60, 0.85),
                (.conditioning, 0.85, 0.96),
                (.emergence, 0.96, 1.00)
            ]
            let templateSegments = templateSpans.map { phase, from, to in
                PhaseSegment(
                    phase: phase,
                    startTime: subject.duration * from,
                    endTime: subject.duration * to,
                    characteristics: phase.displayName,
                    tranceDepthEstimate: phase.tranceDepthEstimate
                )
            }
            let templateSession = generator.generateSession(
                from: audioFile,
                analysis: AnalysisFixtures.hypnosisAnalysis.with(
                    hypnosisMetadata: HypnosisMetadata(
                        phases: templateSegments,
                        inductionStyle: .permissive,
                        estimatedTranceDeph: .medium,
                        suggestionDensity: 0.5,
                        languagePatterns: [],
                        detectedTechniques: []
                    )
                )
            )

            let reference = sample(session(truthBoundaries), duration: subject.duration)
            let detector = sample(session(detectorBoundaries), duration: subject.duration)
            let incumbent = sample(session(incumbentBoundaries), duration: subject.duration)

            let frequencyRange = (reference.frequency.max() ?? 1) - (reference.frequency.min() ?? 0)
            func describe(_ label: String, _ other: (frequency: [Double], intensity: [Double]), _ count: Int) -> String {
                let hz = meanAbsoluteDifference(reference.frequency, other.frequency)
                let brightness = meanAbsoluteDifference(reference.intensity, other.intensity)
                let share = frequencyRange > 0 ? hz / frequencyRange * 100 : 0
                return "     \(label): \(count) boundaries, "
                    + "Δfreq \(hz.formatted(.number.precision(.fractionLength(3)))) Hz "
                    + "(\(Int(share))% of the \(frequencyRange.formatted(.number.precision(.fractionLength(1)))) Hz range), "
                    + "Δintensity \(brightness.formatted(.number.precision(.fractionLength(4))))"
            }

            lines.append("  \(subject.name) — truth has \(truthBoundaries.count) boundaries")
            lines.append(describe("detector ", detector, detectorBoundaries.count))
            lines.append(describe("incumbent", incumbent, incumbentBoundaries.count))
            lines.append(
                describe(
                    "AS SHIPPED",
                    sample(asShipped, duration: subject.duration),
                    incumbentPhases.count - 1
                ) + "   ← own labels too"
            )
            lines.append(
                describe(
                    "END-TO-END",
                    sample(endToEnd, duration: subject.duration),
                    namedSegments.count - 1
                ) + "   ← detector + namer, no truth"
            )
            lines.append(
                describe(
                    "TEMPLATE  ",
                    sample(templateSession, duration: subject.duration),
                    templateSegments.count - 1
                ) + "   ← fixed positional arc, no detection"
            )
            for cliff in [0.10, 0.25, 0.40] {
                let outcome = mergedThenNamed(cliff: cliff)
                lines.append(
                    describe(
                        "  merge \(cliff.formatted(.number.precision(.fractionLength(2))))",
                        sample(outcome.session, duration: subject.duration),
                        outcome.count - 1
                    )
                )
            }
        }

        Attachment.record(lines.joined(separator: "\n"), named: "light-impact.txt")
        #expect(subjects.isEmpty == false)
    }
}
