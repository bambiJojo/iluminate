import Foundation
import Testing
@testable import Ilumionate

struct HomeResumeStateTests {

    private func snapshot(
        contentID: String = "abc",
        kind: ResumablePlaybackKind = .session,
        title: String = "Deep Descent",
        progress: Double = 0.5,
        duration: TimeInterval = 600
    ) -> PlaybackProgressSnapshot {
        PlaybackProgressSnapshot(
            contentID: contentID,
            kind: kind,
            title: title,
            progress: progress,
            duration: duration,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    @Test
    func absentWhenThereIsNothingToResume() {
        #expect(HomeResumeState(snapshot: nil) == nil)
    }

    @Test
    func carriesTitleAndRemainingTime() throws {
        let state = try #require(HomeResumeState(snapshot: snapshot()))
        #expect(state.title == "Deep Descent")
        #expect(state.remaining == 300)
        #expect(state.progress == 0.5)
    }

    @Test
    func remainingNeverGoesNegative() throws {
        let state = try #require(HomeResumeState(snapshot: snapshot(progress: 1.5)))
        #expect(state.remaining == 0)
        #expect(state.progress == 1)
    }

    @Test
    func absentWhenTheContentHasNoDuration() {
        #expect(HomeResumeState(snapshot: snapshot(duration: 0)) == nil)
    }

    @Test
    func keepsTheKindSoTheTapCanRouteToTheRightPlayer() throws {
        let audio = try #require(HomeResumeState(snapshot: snapshot(kind: .audio)))
        #expect(audio.kind == .audio)
        let session = try #require(HomeResumeState(snapshot: snapshot(kind: .session)))
        #expect(session.kind == .session)
    }
}
