//
//  TransitionLabelingDraft.swift
//  LumeLabel
//
//  Editor-only state for separating transition placement from phase naming.
//

import Foundation

nonisolated struct TransitionLabelingDraft: Codable, Sendable {
    enum ReadinessIssue: Equatable, Sendable {
        case noSegments
        case unnamedSegments(Int)
        case incompleteStart
        case incompleteEnd
        case invalidSegment(Int)
        case gap(afterSegment: Int)
        case overlap(afterSegment: Int)

        var message: String {
            switch self {
            case .noSegments:
                return "Mark at least one segment before saving this file."
            case .unnamedSegments:
                return "Name every segment before saving this file."
            case .incompleteStart:
                return "The first segment must begin at the start of the audio."
            case .incompleteEnd:
                return "The final segment must reach the end of the audio."
            case .invalidSegment(let index):
                return "Segment \(index + 1) has no duration."
            case .gap(let index):
                return "There is a gap between segments \(index + 1) and \(index + 2)."
            case .overlap(let index):
                return "Segments \(index + 1) and \(index + 2) overlap."
            }
        }
    }

    struct Segment: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        var startTime: TimeInterval
        var endTime: TimeInterval
        var phase: TrancePhase?
        var notes: String?
    }

    let duration: TimeInterval
    private(set) var segments: [Segment]

    var boundaryCount: Int {
        max(segments.count - 1, 0)
    }

    var unassignedCount: Int {
        segments.count { $0.phase == nil }
    }

    var readinessIssue: ReadinessIssue? {
        guard !segments.isEmpty else { return .noSegments }
        guard unassignedCount == 0 else { return .unnamedSegments(unassignedCount) }
        guard let first = segments.first, let last = segments.last else { return .noSegments }
        guard abs(first.startTime) < 0.001 else { return .incompleteStart }

        for index in segments.indices {
            let segment = segments[index]
            guard segment.endTime > segment.startTime else { return .invalidSegment(index) }
            guard index > 0 else { continue }

            let previousEnd = segments[index - 1].endTime
            if segment.startTime > previousEnd + 0.001 {
                return .gap(afterSegment: index - 1)
            }
            if segment.startTime < previousEnd - 0.001 {
                return .overlap(afterSegment: index - 1)
            }
        }

        guard abs(last.endTime - duration) < 0.001 else { return .incompleteEnd }
        return nil
    }

    var isReadyToSave: Bool {
        readinessIssue == nil
    }

    /// Recovery drafts may contain unnamed segments, but their timeline must
    /// still cover the audio exactly once and remain safe to reopen.
    var isStructurallyValid: Bool {
        let tolerance = 0.001
        guard duration.isFinite, duration > 0,
              let first = segments.first,
              let last = segments.last,
              abs(first.startTime) <= tolerance,
              abs(last.endTime - duration) <= tolerance else {
            return false
        }

        for index in segments.indices {
            let segment = segments[index]
            guard segment.startTime.isFinite,
                  segment.endTime.isFinite,
                  segment.startTime >= 0,
                  segment.endTime <= duration + tolerance,
                  segment.endTime > segment.startTime else {
                return false
            }
            guard index > 0 else { continue }
            guard abs(segment.startTime - segments[index - 1].endTime) <= tolerance else {
                return false
            }
        }
        return true
    }

    var labeledPhases: [LabeledFile.LabeledPhase]? {
        guard isReadyToSave else { return nil }
        return segments.compactMap { segment in
            guard let phase = segment.phase else { return nil }
            return LabeledFile.LabeledPhase(
                id: segment.id,
                phase: phase,
                startTime: segment.startTime,
                endTime: segment.endTime,
                notes: segment.notes
            )
        }
    }

    init(duration: TimeInterval, phases: [LabeledFile.LabeledPhase]) {
        self.duration = max(duration, 0)

        if phases.isEmpty {
            segments = [
                Segment(
                    id: UUID(),
                    startTime: 0,
                    endTime: max(duration, 0),
                    phase: nil,
                    notes: nil
                )
            ]
        } else {
            segments = phases
                .sorted { $0.startTime < $1.startTime }
                .map {
                    Segment(
                        id: $0.id,
                        startTime: $0.startTime,
                        endTime: $0.endTime,
                        phase: $0.phase,
                        notes: $0.notes
                    )
                }
        }
    }

    mutating func markBoundary(at time: TimeInterval, tolerance: TimeInterval = 0.05) {
        guard duration > tolerance * 2 else { return }
        let clampedTime = max(tolerance, min(duration - tolerance, time))

        guard let index = segments.firstIndex(where: {
            clampedTime > $0.startTime + tolerance && clampedTime < $0.endTime - tolerance
        }) else {
            return
        }

        let original = segments[index]
        segments[index].endTime = clampedTime
        segments.insert(
            Segment(
                id: UUID(),
                startTime: clampedTime,
                endTime: original.endTime,
                phase: nil,
                notes: nil
            ),
            at: index + 1
        )
    }

    mutating func moveBoundary(
        startingSegmentID id: Segment.ID,
        to time: TimeInterval,
        minimumSegmentDuration: TimeInterval = 0.05
    ) {
        guard let index = segments.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let earliest = segments[index - 1].startTime + minimumSegmentDuration
        let latest = segments[index].endTime - minimumSegmentDuration
        guard earliest <= latest else { return }

        let clampedTime = max(earliest, min(latest, time))
        segments[index - 1].endTime = clampedTime
        segments[index].startTime = clampedTime
    }

    mutating func removeBoundary(startingSegmentID id: Segment.ID) {
        guard let index = segments.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let left = segments[index - 1]
        let right = segments[index]
        let matchingPhase = left.phase == right.phase ? left.phase : nil

        segments[index - 1] = Segment(
            id: left.id,
            startTime: left.startTime,
            endTime: right.endTime,
            phase: matchingPhase,
            notes: matchingPhase == nil ? nil : left.notes
        )
        segments.remove(at: index)
    }

    @discardableResult
    mutating func assign(_ phase: TrancePhase, toSegmentID id: Segment.ID) -> Segment.ID? {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return nil }
        segments[index].phase = phase

        if let next = segments[(index + 1)...].first(where: { $0.phase == nil }) {
            return next.id
        }
        return segments[..<index].first(where: { $0.phase == nil })?.id
    }
}

/// Durable work-in-progress state. This deliberately lives outside the
/// analyzer corpus because incomplete phase naming is useful editor state but
/// is not valid ground truth for training.
nonisolated struct LabelingWorkInProgress: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let revision: UUID
    let updatedAt: Date
    let fileID: LabeledFile.ID
    let audioSHA256: String
    let fileMetadata: LabeledFile
    let labeling: TransitionLabelingDraft
    let candidateReviews: [TransitionCandidateReview.Record]?
    let analyzerReviewBaseline: TransitionCandidateReview.BlindBaseline?

    init(
        revision: UUID = UUID(),
        updatedAt: Date = Date(),
        file: LabeledFile,
        labeling: TransitionLabelingDraft,
        candidateReviews: [TransitionCandidateReview.Record] = [],
        analyzerReviewBaseline: TransitionCandidateReview.BlindBaseline? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.revision = revision
        self.updatedAt = updatedAt
        self.fileID = file.id
        self.audioSHA256 = file.audioSHA256
        self.fileMetadata = file
        self.labeling = labeling
        self.candidateReviews = candidateReviews.isEmpty ? nil : candidateReviews
        self.analyzerReviewBaseline = analyzerReviewBaseline
    }

    func canRestore(over file: LabeledFile) -> Bool {
        schemaVersion == Self.currentSchemaVersion
            && fileID == file.id
            && audioSHA256 == file.audioSHA256
            && abs(labeling.duration - file.audioDuration) <= 0.001
            && labeling.isStructurallyValid
            && updatedAt >= file.labeledAt
            && containsChanges(comparedTo: file)
    }

    private func containsChanges(comparedTo file: LabeledFile) -> Bool {
        if fileMetadata.expectedFrequencyBand.lower != file.expectedFrequencyBand.lower
            || fileMetadata.expectedFrequencyBand.upper != file.expectedFrequencyBand.upper
            || fileMetadata.labelerNotes != file.labelerNotes {
            return true
        }

        guard let recoveredPhases = labeling.labeledPhases,
              recoveredPhases.count == file.phases.count else {
            return true
        }

        let savedPhases = file.phases.sorted { $0.startTime < $1.startTime }
        return !zip(recoveredPhases, savedPhases).allSatisfy { recovered, saved in
            recovered.id == saved.id
                && recovered.phase == saved.phase
                && abs(recovered.startTime - saved.startTime) <= 0.001
                && abs(recovered.endTime - saved.endTime) <= 0.001
                && recovered.notes == saved.notes
        }
    }
}

private actor LabelingDraftDiskStore {
    func load(from url: URL) throws -> LabelingWorkInProgress? {
        guard FileManager.default.fileExists(atPath: url.path()) else { return nil }
        let decoder = JSONDecoder()
        return try decoder.decode(LabelingWorkInProgress.self, from: Data(contentsOf: url))
    }

    func save(_ draft: LabelingWorkInProgress, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(draft).write(to: url, options: .atomic)
    }
}

/// Staging is synchronous on the main actor so switching files cannot race and
/// lose the latest edit. Disk I/O is isolated on a worker actor for relaunch
/// recovery without blocking the UI.
@MainActor
final class LabelingDraftRecoveryStore {
    static let shared = LabelingDraftRecoveryStore()

    private var stagedDrafts: [URL: LabelingWorkInProgress] = [:]
    private let diskStore = LabelingDraftDiskStore()

    func stage(_ draft: LabelingWorkInProgress, in directory: URL) {
        stagedDrafts[draftURL(for: draft.fileID, in: directory)] = draft
    }

    func recover(fileID: LabeledFile.ID, from directory: URL) async throws -> LabelingWorkInProgress? {
        let url = draftURL(for: fileID, in: directory)
        if let staged = stagedDrafts[url] {
            return staged
        }
        let stored = try await diskStore.load(from: url)
        stagedDrafts[url] = stored
        return stored
    }

    func persist(_ draft: LabelingWorkInProgress, in directory: URL) async throws {
        let url = draftURL(for: draft.fileID, in: directory)
        stagedDrafts[url] = draft
        try await diskStore.save(draft, to: url)
    }

    private func draftURL(for fileID: LabeledFile.ID, in directory: URL) -> URL {
        directory.appending(path: "\(fileID.uuidString).json")
    }
}
