//
//  LabelingSprintController.swift
//  LumeLabel
//
//  Keeps the human labeling task bounded to a small gold-corpus goal.
//

import Foundation
import Observation

@MainActor
@Observable
final class LabelingSprintController {
    private struct Snapshot: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let isActive: Bool
        let targetCount: Int
        let queuedFileIDs: [LabeledFile.ID]
        let deferredFileIDs: [LabeledFile.ID]

        init(
            isActive: Bool,
            targetCount: Int,
            queuedFileIDs: [LabeledFile.ID],
            deferredFileIDs: Set<LabeledFile.ID>
        ) {
            self.schemaVersion = Self.currentSchemaVersion
            self.isActive = isActive
            self.targetCount = targetCount
            self.queuedFileIDs = queuedFileIDs
            self.deferredFileIDs = Array(deferredFileIDs)
        }
    }

    struct Progress: Equatable, Sendable {
        let completedCount: Int
        let targetCount: Int
        let remainingCount: Int
        let deferredCount: Int

        var fractionCompleted: Double {
            guard targetCount > 0 else { return 1 }
            return min(Double(completedCount) / Double(targetCount), 1)
        }
    }

    private(set) var isActive = false
    private(set) var targetCount = 25
    private var queuedFileIDs: [LabeledFile.ID] = []
    private var deferredFileIDs: Set<LabeledFile.ID> = []
    private let defaults: UserDefaults
    private let storageKey = "LumeLabel.goldLabelingSprint"

    var hasPlan: Bool { queuedFileIDs.isEmpty == false }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.schemaVersion == Snapshot.currentSchemaVersion else {
            return
        }
        self.isActive = snapshot.isActive
        self.targetCount = max(snapshot.targetCount, 1)
        self.queuedFileIDs = snapshot.queuedFileIDs
        self.deferredFileIDs = Set(snapshot.deferredFileIDs)
    }

    @discardableResult
    func start(
        files: [LabeledFile],
        targetCount: Int = 25,
        transcribedHashes: Set<String>,
        bambiTranscriptHashes: Set<String> = []
    ) -> LabeledFile.ID? {
        self.targetCount = max(targetCount, 1)
        deferredFileIDs = []

        let completedCount = min(files.count(where: Self.isGold), self.targetCount)
        let neededCount = max(self.targetCount - completedCount, 0)
        let candidates = files.filter {
            Self.isGold($0) == false
                && BambiSafetyPolicy.requiresTranscriptOnlyLabeling(
                    $0,
                    bambiTranscriptHashes: bambiTranscriptHashes
                ) == false
        }
        queuedFileIDs = selectCandidates(
            candidates,
            count: neededCount,
            transcribedHashes: transcribedHashes
        ).map(\.id)
        isActive = queuedFileIDs.isEmpty == false
        persist()
        return queuedFileIDs.first
    }

    func progress(in files: [LabeledFile]) -> Progress {
        let completedCount = min(files.count(where: Self.isGold), targetCount)
        return Progress(
            completedCount: completedCount,
            targetCount: targetCount,
            remainingCount: max(targetCount - completedCount, 0),
            deferredCount: deferredFileIDs.count
        )
    }

    func pause() {
        isActive = false
        persist()
    }

    @discardableResult
    func resume(
        files: [LabeledFile],
        bambiTranscriptHashes: Set<String> = []
    ) -> LabeledFile.ID? {
        // The corpus loads asynchronously at app launch. An empty array at
        // that moment means "not loaded yet," not "every queued file vanished."
        guard files.isEmpty == false else {
            isActive = hasPlan
            persist()
            return nil
        }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        queuedFileIDs.removeAll { id in
            guard let file = filesByID[id] else { return true }
            return Self.isGold(file)
                || BambiSafetyPolicy.requiresTranscriptOnlyLabeling(
                    file,
                    bambiTranscriptHashes: bambiTranscriptHashes
                )
        }
        isActive = queuedFileIDs.isEmpty == false
        persist()
        return queuedFileIDs.first
    }

    @discardableResult
    func deferFile(
        fileID: LabeledFile.ID,
        files: [LabeledFile],
        transcribedHashes: Set<String>,
        bambiTranscriptHashes: Set<String> = []
    ) -> LabeledFile.ID? {
        deferredFileIDs.insert(fileID)
        queuedFileIDs.removeAll { $0 == fileID }

        let completedCount = min(files.count(where: Self.isGold), targetCount)
        let desiredQueueCount = max(targetCount - completedCount, 0)
        let excludedIDs = Set(queuedFileIDs).union(deferredFileIDs)
        let replacements = files.filter {
            Self.isGold($0) == false
                && BambiSafetyPolicy.requiresTranscriptOnlyLabeling(
                    $0,
                    bambiTranscriptHashes: bambiTranscriptHashes
                ) == false
                && excludedIDs.contains($0.id) == false
        }

        let replacementCount = max(desiredQueueCount - queuedFileIDs.count, 0)
        queuedFileIDs.append(contentsOf: selectCandidates(
            replacements,
            count: replacementCount,
            transcribedHashes: transcribedHashes
        ).map(\.id))
        isActive = queuedFileIDs.isEmpty == false
        persist()
        return queuedFileIDs.first
    }

    @discardableResult
    func advanceAfterSaving(
        fileID: LabeledFile.ID,
        files: [LabeledFile],
        bambiTranscriptHashes: Set<String> = []
    ) -> LabeledFile.ID? {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        queuedFileIDs.removeAll { id in
            id == fileID
                || filesByID[id].map {
                    Self.isGold($0) || BambiSafetyPolicy.requiresTranscriptOnlyLabeling(
                        $0,
                        bambiTranscriptHashes: bambiTranscriptHashes
                    )
                } != false
        }
        isActive = queuedFileIDs.isEmpty == false
        persist()
        return queuedFileIDs.first
    }

    func queuedFiles(
        from files: [LabeledFile],
        bambiTranscriptHashes: Set<String> = []
    ) -> [LabeledFile] {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        return queuedFileIDs.compactMap { id in
            guard let file = filesByID[id],
                  Self.isGold(file) == false,
                  BambiSafetyPolicy.requiresTranscriptOnlyLabeling(
                    file,
                    bambiTranscriptHashes: bambiTranscriptHashes
                  ) == false else {
                return nil
            }
            return file
        }
    }

    private nonisolated static func isGold(_ file: LabeledFile) -> Bool {
        file.phases.isEmpty == false && file.analyzerLabelTrust.isTrustedForLearning
    }

    private func selectCandidates(
        _ candidates: [LabeledFile],
        count: Int,
        transcribedHashes: Set<String>
    ) -> [LabeledFile] {
        guard count > 0, candidates.isEmpty == false else { return [] }
        let byDuration = candidates.sorted {
            if $0.audioDuration != $1.audioDuration {
                return $0.audioDuration < $1.audioDuration
            }
            return $0.audioFilename.localizedStandardCompare($1.audioFilename) == .orderedAscending
        }

        let selected: [LabeledFile]
        if count >= byDuration.count {
            selected = byDuration
        } else if count == 1 {
            selected = [byDuration[byDuration.count / 2]]
        } else {
            selected = (0..<count).map { index in
                let fraction = Double(index) / Double(count - 1)
                let candidateIndex = Int((fraction * Double(byDuration.count - 1)).rounded())
                return byDuration[candidateIndex]
            }
        }

        return selected.sorted {
            let lhsHasTranscript = transcribedHashes.contains($0.audioSHA256)
            let rhsHasTranscript = transcribedHashes.contains($1.audioSHA256)
            if lhsHasTranscript != rhsHasTranscript {
                return lhsHasTranscript
            }
            if $0.audioDuration != $1.audioDuration {
                return $0.audioDuration < $1.audioDuration
            }
            return $0.audioFilename.localizedStandardCompare($1.audioFilename) == .orderedAscending
        }
    }

    private func persist() {
        let snapshot = Snapshot(
            isActive: isActive,
            targetCount: targetCount,
            queuedFileIDs: queuedFileIDs,
            deferredFileIDs: deferredFileIDs
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
