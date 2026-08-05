//  ReaderControlSlotTests.swift
//  IlumionateTests
//
//  The reader tray's composition rules, mirroring the player's.

import Foundation
import Testing
@testable import Ilumionate

@Suite("Reader control slots")
struct ReaderControlSlotTests {

    @Test("The tray never exceeds the player's density")
    func trayStaysDense() {
        #expect(ReaderControlSlot.slots.count <= 5)
        #expect(!ReaderControlSlot.slots.isEmpty)
    }

    @Test("Slots are unique — no tile is rendered twice")
    func slotsAreUnique() {
        #expect(Set(ReaderControlSlot.slots).count == ReaderControlSlot.slots.count)
    }

    @Test("The tray carries every control the reader asked for")
    func trayHasTheWantedControls() {
        #expect(ReaderControlSlot.slots.contains(.speed))
        #expect(ReaderControlSlot.slots.contains(.visual))
        #expect(ReaderControlSlot.slots.contains(.readerMode))
        #expect(ReaderControlSlot.slots.contains(.tranceMode))
        #expect(ReaderControlSlot.slots.contains(.more))
    }

    /// The Trance tile lives in the tray, so a mode-dependent tray would
    /// reshuffle tiles under the finger that just tapped one.
    @Test("The tray is mode-invariant so toggling trance cannot reflow it")
    func trayIsModeInvariant() {
        let before = ReaderControlSlot.slots
        for _ in ReaderMode.allCases {
            #expect(ReaderControlSlot.slots == before)
        }
    }

    @Test("Speed and Trance are the value tiles; the rest are taps")
    func draggableSlots() {
        let draggable: Set<ReaderControlSlot> = [.speed, .tranceMode]
        for slot in ReaderControlSlot.allCases {
            #expect(slot.isDraggable == draggable.contains(slot))
        }
    }

    @Test("Labels never change with state, so the tray cannot reflow")
    func labelsAreConstant() {
        // The old satellite row flipped between "Binaural on" and "Binaural off".
        for slot in ReaderControlSlot.allCases {
            #expect(!slot.label.localizedStandardContains("on"))
            #expect(!slot.label.localizedStandardContains("off"))
        }
    }

    /// Disabling it at zero would strip the drag gesture the instant it reached
    /// off, leaving no way to drag back up.
    @Test("Trance stays live even with the visuals off")
    func tranceStaysLive() {
        #expect(ReaderControlSlot.tranceMode.state(visualOn: true) == .normal)
        #expect(ReaderControlSlot.tranceMode.state(visualOn: false) == .normal)
    }

    @Test("Trance still shows on/off in its icon")
    func tranceIconTracksOnOff() {
        let on = ReaderControlSlot.tranceMode.systemImage(colorMode: .dark, visualOn: true)
        let off = ReaderControlSlot.tranceMode.systemImage(colorMode: .dark, visualOn: false)
        #expect(on != off)
    }

    @Test("Visual reads as unavailable while the visuals are off")
    func visualDisabledWhenOff() {
        #expect(ReaderControlSlot.visual.state(visualOn: false) == .disabled)
        #expect(ReaderControlSlot.visual.state(visualOn: true) == .normal)
    }

    @Test("Display tile shows a distinct icon per colour mode")
    func displayIconTracksColorMode() {
        let icons = ReaderColorMode.allCases.map {
            ReaderControlSlot.readerMode.systemImage(colorMode: $0, visualOn: true)
        }
        #expect(Set(icons).count == ReaderColorMode.allCases.count)
    }

    @Test("Display tile cycles Auto to Light to Dark and back")
    func colorModeCycles() {
        #expect(ReaderColorMode.followApp.next == .light)
        #expect(ReaderColorMode.light.next == .dark)
        #expect(ReaderColorMode.dark.next == .followApp)

        // Cycling the full length returns to the start, so no mode is stranded.
        var mode = ReaderColorMode.followApp
        for _ in ReaderColorMode.allCases { mode = mode.next }
        #expect(mode == .followApp)
    }

    @Test("Cycling reaches every effect and wraps")
    func visualCycles() throws {
        let effects = ReaderVisual.effects
        var visual = try #require(effects.first)
        var seen: Set<ReaderVisual> = [visual]
        for _ in effects {
            visual = visual.nextEffect
            seen.insert(visual)
        }
        // Every effect is reachable by tapping alone…
        #expect(seen == Set(effects))
        // …and a full lap returns to the start, so nothing is stranded.
        #expect(visual == effects.first)
    }

    /// Turning the visuals off belongs to the Trance tile, so cycling must never
    /// strand the reader on a blank background.
    @Test("Cycling never lands on none")
    func visualCycleSkipsOff() {
        #expect(!ReaderVisual.effects.contains(.none))
        for visual in ReaderVisual.effects {
            #expect(visual.nextEffect != .none)
        }
        // Even from the off state, stepping produces a real effect.
        #expect(ReaderVisual.none.nextEffect != .none)
    }

    @Test("There is exactly one effect fewer than there are cases")
    func effectsExcludeOnlyNone() {
        #expect(ReaderVisual.effects.count == ReaderVisual.allCases.count - 1)
    }
}
