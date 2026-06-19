//  PacingSleepController.swift
//  IlumionateTests

import Foundation
@testable import Ilumionate

/// Step-controllable sleep for driver tests. Each call increments `callCount`
/// and invokes `onSleep(callCount)` so a test can trigger pause/resume/settings
/// changes at a precise word boundary. Returns immediately (no real delay).
@MainActor
final class PacingSleepController {
    private(set) var callCount = 0
    var onSleep: (Int) -> Void = { _ in }

    func sleep(_ duration: Duration) async {
        callCount += 1
        onSleep(callCount)
    }

    /// The closure to inject into `TextTranceSession(sleep:)`.
    var sleepClosure: @Sendable (Duration) async -> Void {
        { [self] duration in await self.sleep(duration) }
    }
}
