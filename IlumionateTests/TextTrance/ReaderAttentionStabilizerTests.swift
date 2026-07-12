import Testing
@testable import Ilumionate

struct ReaderAttentionStabilizerTests {
    @Test func briefAttentionLossDoesNotPause() {
        var stabilizer = ReaderAttentionStabilizer(lossGrace: 1.5, now: 10)

        let afterBlink = stabilizer.observe(isLookingAtScreen: false, at: 10.2)
        let beforeGraceExpires = stabilizer.observe(isLookingAtScreen: false, at: 11.4)
        #expect(afterBlink)
        #expect(beforeGraceExpires)
    }

    @Test func sustainedAttentionLossPauses() {
        var stabilizer = ReaderAttentionStabilizer(lossGrace: 1.5, now: 10)

        let afterGraceExpires = stabilizer.observe(isLookingAtScreen: false, at: 11.5)
        #expect(!afterGraceExpires)
    }

    @Test func attentiveFrameResumesImmediatelyAndRestartsGracePeriod() {
        var stabilizer = ReaderAttentionStabilizer(lossGrace: 1.5, now: 10)
        let afterLoss = stabilizer.observe(isLookingAtScreen: false, at: 12)
        #expect(!afterLoss)

        let afterReturn = stabilizer.observe(isLookingAtScreen: true, at: 12.1)
        let duringNewGracePeriod = stabilizer.observe(isLookingAtScreen: false, at: 13.5)
        #expect(afterReturn)
        #expect(duringNewGracePeriod)
    }
}

struct ReaderAttentionDecisionTests {
    @Test func headFacingScreenWithOpenEyesCountsAsReading() {
        // Normal reading posture: head pointed at the phone, eyes open.
        #expect(ReaderAttentionSample.isLooking(
            headFacing: 0.92, eyesClosed: 0.05, faceTracked: true))
    }

    @Test func slightHeadTiltStillCountsAsReading() {
        // Reading with a comfortable downward tilt must not trip the gate —
        // this is the exact case the old eyeball-gaze heuristic failed.
        #expect(ReaderAttentionSample.isLooking(
            headFacing: 0.6, eyesClosed: 0.2, faceTracked: true))
    }

    @Test func headTurnedAwayIsNotReading() {
        #expect(!ReaderAttentionSample.isLooking(
            headFacing: 0.1, eyesClosed: 0.0, faceTracked: true))
    }

    @Test func bothEyesShutIsNotReading() {
        #expect(!ReaderAttentionSample.isLooking(
            headFacing: 0.95, eyesClosed: 0.9, faceTracked: true))
    }

    @Test func untrackedFaceIsNotReading() {
        #expect(!ReaderAttentionSample.isLooking(
            headFacing: 1.0, eyesClosed: 0.0, faceTracked: false))
    }
}
