import Foundation
import Observation

nonisolated enum ResumablePlaybackKind: String, Codable, Sendable {
    case session, audio
}

nonisolated struct PlaybackProgressSnapshot: Codable, Identifiable, Equatable, Sendable {
    let contentID: String
    let kind: ResumablePlaybackKind
    let title: String
    let progress: Double
    let duration: TimeInterval
    let updatedAt: Date

    var id: String { contentID }
}

@MainActor
@Observable
final class PlaybackProgressStore {
    static let shared = PlaybackProgressStore()
    static let storageKey = "playbackProgressSnapshots_v1"

    private(set) var snapshots: [PlaybackProgressSnapshot] = []
    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        load()
    }

    func snapshot(for contentID: String) -> PlaybackProgressSnapshot? {
        snapshots.first { $0.contentID == contentID }
    }

    func save(
        contentID: String,
        kind: ResumablePlaybackKind,
        title: String,
        progress: Double,
        duration: TimeInterval
    ) {
        guard progress > 0.01, progress < 0.99, duration > 0 else {
            clear(contentID: contentID)
            return
        }
        let snapshot = PlaybackProgressSnapshot(
            contentID: contentID,
            kind: kind,
            title: title,
            progress: min(max(progress, 0), 1),
            duration: duration,
            updatedAt: now()
        )
        snapshots.removeAll { $0.contentID == contentID }
        snapshots.insert(snapshot, at: 0)
        snapshots = Array(snapshots.prefix(20))
        persist()
    }

    func clear(contentID: String) {
        guard snapshots.contains(where: { $0.contentID == contentID }) else { return }
        snapshots.removeAll { $0.contentID == contentID }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([PlaybackProgressSnapshot].self, from: data) else {
            return
        }
        snapshots = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
