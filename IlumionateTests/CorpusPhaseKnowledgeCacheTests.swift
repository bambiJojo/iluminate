import Foundation
import Testing
@testable import Ilumionate

struct CorpusPhaseKnowledgeCacheTests {

    @Test func repeatedReadsUseOneLoadedSnapshot() {
        let counter = LockedCounter()
        let cache = CorpusPhaseKnowledgeCache {
            counter.increment()
            return CorpusPhaseKnowledge(keywordWeights: [.induction: ["breathe": 2.0]])
        }

        _ = cache.knowledge()
        _ = cache.knowledge()

        #expect(counter.value == 1)
    }

    @Test func invalidationLoadsOneNewSnapshot() {
        let counter = LockedCounter()
        let cache = CorpusPhaseKnowledgeCache {
            counter.increment()
            return .empty
        }

        _ = cache.knowledge()
        cache.invalidate()
        _ = cache.knowledge()

        #expect(counter.value == 2)
    }

    @Test func recursiveLoaderUsesEmptyBootstrapKnowledge() {
        let holder = KnowledgeCacheHolder()
        let cache = CorpusPhaseKnowledgeCache {
            let bootstrap = holder.cache.knowledge()
            holder.sawEmptyBootstrap = bootstrap.keywordWeights.isEmpty
            return CorpusPhaseKnowledge(keywordWeights: [.induction: ["breathe": 2.0]])
        }
        holder.cache = cache

        let knowledge = cache.knowledge()

        #expect(holder.sawEmptyBootstrap)
        #expect(knowledge.keywordWeights[.induction]?["breathe"] == 2.0)
    }
}

private nonisolated final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}

private nonisolated final class KnowledgeCacheHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var cacheStorage: CorpusPhaseKnowledgeCache?
    private var sawEmptyBootstrapStorage = false

    var cache: CorpusPhaseKnowledgeCache {
        get { lock.withLock { cacheStorage! } }
        set { lock.withLock { cacheStorage = newValue } }
    }

    var sawEmptyBootstrap: Bool {
        get { lock.withLock { sawEmptyBootstrapStorage } }
        set { lock.withLock { sawEmptyBootstrapStorage = newValue } }
    }
}
