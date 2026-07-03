//  BloomStateTests.swift
//  IlumionateTests

import Testing
@testable import Ilumionate

struct BloomStateTests {
    private enum Panel { case volume, light }

    @Test func togglingOpensThenCloses() {
        var state = BloomState<Panel>()
        #expect(state.open == nil)
        state.toggle(.volume)
        #expect(state.isOpen(.volume))
        state.toggle(.volume)
        #expect(state.open == nil)
    }

    @Test func togglingAnotherPanelSwitchesExclusively() {
        var state = BloomState<Panel>()
        state.toggle(.volume)
        state.toggle(.light)
        #expect(state.isOpen(.light))
        #expect(!state.isOpen(.volume))
    }

    @Test func closeAllClears() {
        var state = BloomState<Panel>()
        state.toggle(.volume)
        state.closeAll()
        #expect(state.open == nil)
    }
}
