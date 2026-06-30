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
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}
