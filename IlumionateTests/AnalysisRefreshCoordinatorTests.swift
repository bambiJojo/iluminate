//
//  AnalysisRefreshCoordinatorTests.swift
//  IlumionateTests
//
//  Structural refresh is async; progress refresh is synchronous and frequent.
//  Without a generation guard a slow structural read commits over newer
//  progress. These tests pin the four rules that prevent that.
//

import Testing
import Foundation
@testable import Ilumionate

/// One-shot gate so a test can hold a pass open deterministically, without
/// sleeping on wall-clock time.
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

/// Main-actor counter. A plain `var` captured by an `@escaping` closure is not
/// expressible under strict concurrency.
@MainActor
private final class Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@MainActor
private final class Recorder {
    private(set) var values: [Int] = []
    func record(_ value: Int) { values.append(value) }
}

@MainActor
struct AnalysisRefreshCoordinatorTests {

    /// Rule 2: a burst of invalidations during an in-flight pass collapses into
    /// exactly one further pass, not one per invalidation.
    @Test func burstOfInvalidationsCoalescesIntoOneFurtherPass() async {
        let passes = Counter()
        let gate = AsyncGate()
        let coordinator = AnalysisRefreshCoordinator<Int>(load: {
            passes.increment()
            await gate.wait()
            return 0
        })

        coordinator.invalidate()
        await Task.yield()
        for _ in 0..<10 { coordinator.invalidate() }
        await gate.open()
        await coordinator.drain()

        #expect(passes.value == 2)
    }

    /// Rule 3: a slow pass that started earlier must not commit over a newer one.
    @Test func staleGenerationIsDiscardedAtCommit() async {
        let recorder = Recorder()
        let coordinator = AnalysisRefreshCoordinator<Int>(
            load: { 0 },
            commit: { recorder.record($0) }
        )
        coordinator.commitIfCurrent(value: 1, generation: 5)
        coordinator.commitIfCurrent(value: 2, generation: 3)   // older, must be dropped
        coordinator.commitIfCurrent(value: 3, generation: 6)

        #expect(recorder.values == [1, 3])
    }

    @Test func invalidationBeforeFirstLoadIsNotLost() async {
        let passes = Counter()
        let coordinator = AnalysisRefreshCoordinator<Int>(load: {
            passes.increment()
            return 0
        })
        coordinator.invalidate()          // raised before any pass has started
        await coordinator.drain()
        #expect(passes.value >= 1)
    }

    @Test func drainReturnsOnlyWhenNoPassIsPending() async {
        let passes = Counter()
        let coordinator = AnalysisRefreshCoordinator<Int>(load: {
            passes.increment()
            return 0
        })
        coordinator.invalidate()
        await coordinator.drain()
        let settled = passes.value
        await coordinator.drain()
        #expect(passes.value == settled)
    }
}
