//
//  AnalysisRefreshCoordinator.swift
//  Ilumionate
//
//  Coalesces structural refreshes behind a generation guard.
//
//  Structural refresh is async (disk, actor hops); progress refresh is
//  synchronous and frequent. Without a guard, a slow structural read can commit
//  after a newer progress tick and rewind it. Generic over the loaded value so
//  the concurrency rules are testable without disk or SwiftUI.
//

import Foundation

// Keep destruction nonisolated. Xcode 26.5's Swift optimizer crashes while
// lowering a generic global-actor-isolated deinitializer for iOS 18. The public
// behavior remains main-actor-isolated through the explicit annotations below.
nonisolated final class AnalysisRefreshCoordinator<Value> {

    private let load: @MainActor () async -> Value
    private let commit: @MainActor (Value) -> Void

    private var generation = 0
    private var committedGeneration = -1
    private var isLoading = false
    private var isDirty = false
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    @MainActor
    init(
        load: @escaping @MainActor () async -> Value,
        commit: @escaping @MainActor (Value) -> Void = { _ in }
    ) {
        self.load = load
        self.commit = commit
    }

    /// Request a structural refresh. Safe to call from any mutation site; calls
    /// arriving during an in-flight pass set a dirty flag rather than starting
    /// a second pass, so importing forty files costs two passes, not forty.
    @MainActor
    func invalidate() {
        guard !isLoading else {
            isDirty = true
            return
        }
        startPass()
    }

    /// Commit a loaded value only if no newer pass has already committed.
    @MainActor
    func commitIfCurrent(value: Value, generation passGeneration: Int) {
        guard passGeneration > committedGeneration else { return }
        committedGeneration = passGeneration
        commit(value)
    }

    /// Resumes once no pass is in flight and nothing is pending. Test support;
    /// production code never needs to wait for a refresh.
    @MainActor
    func drain() async {
        guard isLoading || isDirty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }

    // MARK: Private

    @MainActor
    private func startPass() {
        isLoading = true
        generation += 1
        let passGeneration = generation
        Task { @MainActor in
            let value = await load()
            commitIfCurrent(value: value, generation: passGeneration)
            isLoading = false
            if isDirty {
                isDirty = false
                startPass()
            } else {
                let waiters = drainWaiters
                drainWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
    }
}
