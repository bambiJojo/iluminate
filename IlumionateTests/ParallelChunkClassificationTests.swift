//
//  ParallelChunkClassificationTests.swift
//  IlumionateTests
//
//  Tests for Step 4.5: Two-pass parallel chunk classification.
//  Verifies:
//  1. evenOddIndices produces correct even/odd splits for any count.
//  2. Even and odd sets are disjoint and their union covers every index.
//  3. Every odd index has a valid preceding even index (i-1 is always even).
//  4. Edge cases: count=0, count=1, count=2, large odd/even counts.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - evenOddIndices structural tests

struct EvenOddIndicesTests {

    @Test func zeroChunksProducesEmptySets() {
        let (even, odd) = ChunkedPhaseAnalyzer.evenOddIndices(count: 0)
        #expect(even.isEmpty, "even must be empty for count=0")
        #expect(odd.isEmpty,  "odd must be empty for count=0")
    }

    @Test func singleChunkIsEven() {
        let (even, odd) = ChunkedPhaseAnalyzer.evenOddIndices(count: 1)
        #expect(even == [0], "single chunk must be even index 0")
        #expect(odd.isEmpty,  "no odd indices for count=1")
    }

    @Test func twoChunksSplitCorrectly() {
        let (even, odd) = ChunkedPhaseAnalyzer.evenOddIndices(count: 2)
        #expect(even == [0], "even: [0]")
        #expect(odd  == [1], "odd:  [1]")
    }

    @Test func sixChunksSplitIntoThreeAndThree() {
        let (even, odd) = ChunkedPhaseAnalyzer.evenOddIndices(count: 6)
        #expect(even == [0, 2, 4], "even chunks for count=6")
        #expect(odd  == [1, 3, 5], "odd chunks for count=6")
    }

    @Test func sevenChunksSplitFourAndThree() {
        let (even, odd) = ChunkedPhaseAnalyzer.evenOddIndices(count: 7)
        #expect(even == [0, 2, 4, 6], "even chunks for count=7")
        #expect(odd  == [1, 3, 5],    "odd chunks for count=7")
    }

    @Test func evenAndOddAreDisjoint() {
        for count in [0, 1, 2, 5, 6, 10, 20, 40, 60] {
            let (even, odd) = ChunkedPhaseAnalyzer.evenOddIndices(count: count)
            let evenSet = Set(even)
            let oddSet  = Set(odd)
            #expect(evenSet.isDisjoint(with: oddSet),
                "Even and odd sets must be disjoint for count=\(count)")
        }
    }

    @Test func evenUnionOddCoversAllIndices() {
        for count in [0, 1, 2, 5, 6, 10, 20, 40, 60] {
            let (even, odd) = ChunkedPhaseAnalyzer.evenOddIndices(count: count)
            let union = Set(even).union(Set(odd))
            let expected = Set(0..<count)
            #expect(union == expected,
                "Even ∪ odd must equal 0..<\(count), got \(union.sorted())")
        }
    }

    @Test func everyOddIndexHasPrecedingEvenIndex() {
        // The two-pass scheme reads results[oddIndex - 1] for context.
        // That slot must always be an even index (guaranteed by parity).
        for count in [2, 3, 5, 6, 7, 20, 60] {
            let (_, odd) = ChunkedPhaseAnalyzer.evenOddIndices(count: count)
            for oddIdx in odd {
                let predecessor = oddIdx - 1
                #expect(predecessor >= 0,
                    "Odd index \(oddIdx) has no predecessor (count=\(count))")
                #expect(predecessor.isMultiple(of: 2),
                    "Predecessor of odd index \(oddIdx) must be even, got \(predecessor)")
            }
        }
    }

    @Test func evenIndicesAreMonotonicallyIncreasing() {
        let (even, _) = ChunkedPhaseAnalyzer.evenOddIndices(count: 40)
        #expect(even == even.sorted(), "Even indices must be sorted ascending")
    }

    @Test func oddIndicesAreMonotonicallyIncreasing() {
        let (_, odd) = ChunkedPhaseAnalyzer.evenOddIndices(count: 40)
        #expect(odd == odd.sorted(), "Odd indices must be sorted ascending")
    }

    @Test func chunkCountOfSixtyProducesThirtyAndThirty() {
        let (even, odd) = ChunkedPhaseAnalyzer.evenOddIndices(count: 60)
        #expect(even.count == 30, "60 chunks → 30 even, got \(even.count)")
        #expect(odd.count  == 30, "60 chunks → 30 odd,  got \(odd.count)")
    }
}
