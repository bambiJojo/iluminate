import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct SystemNowPlayingTransportTests {
    @Test("Remote toggle follows the player through play, pause, resume and stop", .timeLimit(.minutes(1)))
    func remoteToggleUsesPlayerState() async throws {
        let suiteName = "SystemNowPlayingTransportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "hasSeenFlashWarning")
        defaults.set(3, forKey: "countdownDuration")
        let player = UnifiedPlayerViewModel(
            mode: .colorPulse(frequency: 8, intensity: 0),
            engine: LightEngine(),
            userDefaults: defaults
        )
        player.onAppear()
        defer { player.onDisappear() }
        let remote = player.systemNowPlayingHandlers

        remote.togglePlayPause()
        #expect(player.playbackState == .idle)

        player.togglePlayPause()
        remote.togglePlayPause()
        #expect(player.playbackState == .countdown)

        player.skipCountdown()
        // Full-suite MainActor contention can delay one 20 ms suspension by
        // more than eight seconds, before the countdown task resumes. Bound
        // polling attempts instead of charging unrelated work to a wall-clock
        // deadline. The test-level limit still catches a stalled transition.
        for _ in 0..<400 {
            guard player.playbackState == .countdown else { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(player.playbackState == .playing)

        remote.togglePlayPause()
        #expect(player.playbackState == .paused)
        remote.togglePlayPause()
        #expect(player.playbackState == .playing)
        remote.pause()
        #expect(player.playbackState == .paused)
        remote.play()
        #expect(player.playbackState == .playing)

        player.stopAll()
        remote.togglePlayPause()
        #expect(player.playbackState == .idle)
    }
}
