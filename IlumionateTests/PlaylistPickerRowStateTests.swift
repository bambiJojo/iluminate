//
//  PlaylistPickerRowStateTests.swift
//  IlumionateTests
//
//  A TestFlight tester reported that imported audio "doesn't load or save":
//  their five files were in the library, but the playlist picker offered no
//  way to act on them because they had not been analyzed yet. These tests pin
//  the rule that every row is either selectable or offers a way forward — no
//  row is ever an inert dead end.
//

import Testing

@testable import Ilumionate

@Suite("Playlist picker row state")
struct PlaylistPickerRowStateTests {

    // MARK: - Resolution

    @Test("A file with a generated session is selectable")
    func generatedSessionIsReady() {
        let state = PlaylistPickerRowState.resolve(
            hasGeneratedSession: true,
            isAlreadyAdded: false,
            isAnalyzing: false
        )

        #expect(state == .ready)
        #expect(state.isSelectable)
    }

    @Test("An un-analyzed file offers analysis rather than doing nothing")
    func unanalyzedFileOffersAnalysis() {
        let state = PlaylistPickerRowState.resolve(
            hasGeneratedSession: false,
            isAlreadyAdded: false,
            isAnalyzing: false
        )

        #expect(state == .needsAnalysis)
        #expect(state.canStartAnalysis)
    }

    @Test("A file being analyzed reports progress instead of re-queueing")
    func analyzingFileCannotBeRequeued() {
        let state = PlaylistPickerRowState.resolve(
            hasGeneratedSession: false,
            isAlreadyAdded: false,
            isAnalyzing: true
        )

        #expect(state == .analyzing)
        #expect(state.canStartAnalysis == false)
        #expect(state.isSelectable == false)
    }

    @Test("Already-added wins over every other signal")
    func alreadyAddedTakesPrecedence() {
        for hasSession in [true, false] {
            for isAnalyzing in [true, false] {
                let state = PlaylistPickerRowState.resolve(
                    hasGeneratedSession: hasSession,
                    isAlreadyAdded: true,
                    isAnalyzing: isAnalyzing
                )

                #expect(state == .alreadyAdded)
                #expect(state.isSelectable == false)
            }
        }
    }

    @Test("A ready file stays ready while a re-analysis runs")
    func readyBeatsAnalyzing() {
        let state = PlaylistPickerRowState.resolve(
            hasGeneratedSession: true,
            isAlreadyAdded: false,
            isAnalyzing: true
        )

        #expect(state == .ready)
    }

    // MARK: - The regression this fixes

    @Test("No state is a dead end", arguments: PlaylistPickerRowState.allCases)
    func everyStateOffersAWayForward(state: PlaylistPickerRowState) {
        // Either the row can be acted on now, or it is already resolved
        // (added / in flight). The reported bug was a row that was none of
        // these — visible, disabled, and silent on tap.
        let isResolved = state == .alreadyAdded || state == .analyzing
        #expect(state.isSelectable || state.canStartAnalysis || isResolved)
    }

    @Test("Only ready rows count toward the add button")
    func onlyReadyRowsAreSelectable() {
        let selectable = PlaylistPickerRowState.allCases.filter(\.isSelectable)

        #expect(selectable == [.ready])
    }
}
