import Foundation

/// Tracks meaningful progress for a single analysis attempt using elapsed,
/// monotonic time supplied by the coordinator.
nonisolated struct AnalysisInactivityWatchdog: Sendable {
    private(set) var stage: AnalyticsAnalysisStage
    private(set) var progress: Double
    private(set) var lastHeartbeatAt: Duration
    let timeout: Duration

    init(
        stage: AnalyticsAnalysisStage,
        progress: Double,
        startedAt: Duration,
        timeout: Duration
    ) {
        self.stage = stage
        self.progress = progress
        self.lastHeartbeatAt = startedAt
        self.timeout = timeout
    }

    mutating func observe(
        stage newStage: AnalyticsAnalysisStage,
        progress newProgress: Double,
        at timestamp: Duration
    ) {
        guard newStage != stage || newProgress > progress else { return }

        stage = newStage
        progress = newProgress
        lastHeartbeatAt = timestamp
    }

    func hasTimedOut(at timestamp: Duration) -> Bool {
        timestamp - lastHeartbeatAt >= timeout
    }
}

/// Injectable monotonic time source. Production uses `ContinuousClock`; tests
/// can shorten or fully control the elapsed-time window without using dates.
nonisolated struct AnalysisWatchdogTiming: Sendable {
    let elapsed: @Sendable () -> Duration
    let sleep: @Sendable (Duration) async throws -> Void

    static func continuous() -> Self {
        let clock = ContinuousClock()
        let origin = clock.now
        return Self(
            elapsed: { origin.duration(to: clock.now) },
            sleep: { duration in try await clock.sleep(for: duration) }
        )
    }
}

nonisolated struct AnalysisWatchdogPolicy: Sendable {
    let noProgressTimeout: Duration
    let pollInterval: Duration
    let timing: AnalysisWatchdogTiming

    init(
        noProgressTimeout: Duration = .seconds(300),
        pollInterval: Duration = .seconds(1),
        timing: AnalysisWatchdogTiming = .continuous()
    ) {
        self.noProgressTimeout = noProgressTimeout
        self.pollInterval = pollInterval
        self.timing = timing
    }
}

nonisolated struct AnalysisStalledError: LocalizedError, Sendable {
    let stage: AnalyticsAnalysisStage

    var errorDescription: String? {
        "Analysis made no progress for five minutes during \(stage.rawValue)."
    }
}

nonisolated enum SupervisedAnalysisOutcome<Value: Sendable>: Sendable {
    case result(Result<Value, any Error>)
    case stalled
    case cancelled
}

/// A one-shot race that does not impose structured-concurrency teardown on the
/// winner. That matters when the losing model operation is precisely the task
/// that has stopped responding.
actor AnalysisOperationRace<Value: Sendable> {
    private var outcome: SupervisedAnalysisOutcome<Value>?
    private var waiters: [CheckedContinuation<SupervisedAnalysisOutcome<Value>, Never>] = []

    func resolve(_ candidate: SupervisedAnalysisOutcome<Value>) {
        guard outcome == nil else { return }
        outcome = candidate
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: candidate) }
    }

    func value() async -> SupervisedAnalysisOutcome<Value> {
        if let outcome { return outcome }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
