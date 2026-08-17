//
//  CreateControlSlotTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct CreateControlSlotTests {

    @Test("Each kind's tray is pinned")
    func trays() {
        #expect(CreateControlSlot.slots(for: .visualField)
                == [.effect, .tint, .visualSpeed, .strength, .direction, .duration])
        #expect(CreateControlSlot.slots(for: .flash)
                == [.frequency, .intensity, .warmth, .waveform, .binaural, .duration])
        #expect(CreateControlSlot.slots(for: .bilateral)
                == [.frequency, .intensity, .warmth, .waveform, .binaural, .duration])
        #expect(CreateControlSlot.slots(for: .colourPulse)
                == [.frequency, .intensity, .duration])
    }

    @Test("A tray is the same list every time it is asked for")
    func traysAreStable() {
        // slots(for:) takes only the kind, so no value change can add or remove
        // a tile and the tray cannot reflow under a dragging finger.
        for kind in CreateSessionKind.allCases {
            #expect(CreateControlSlot.slots(for: kind) == CreateControlSlot.slots(for: kind))
        }
    }

    @Test("No tray repeats a slot")
    func noDuplicateSlots() {
        for kind in CreateSessionKind.allCases {
            let slots = CreateControlSlot.slots(for: kind)
            #expect(Set(slots).count == slots.count)
        }
    }

    @Test("Every tray fits the two-rows-of-three layout")
    func traysFitTheLayout() {
        for kind in CreateSessionKind.allCases {
            let count = CreateControlSlot.slots(for: kind).count
            #expect(count >= 1)
            #expect(count <= 6)
        }
    }

    @Test("Every kind offers a duration, because any session can be timed")
    func everyKindCanBeTimed() {
        for kind in CreateSessionKind.allCases {
            #expect(CreateControlSlot.slots(for: kind).contains(.duration))
        }
    }

    @Test("The visual field's tray carries no light-engine controls")
    func visualFieldHasNoLightControls() {
        let slots = CreateControlSlot.slots(for: .visualField)
        for lightOnly in [CreateControlSlot.frequency, .intensity, .warmth, .waveform] {
            #expect(slots.contains(lightOnly) == false)
        }
    }

    @Test("The light kinds carry no visual-field controls")
    func lightKindsHaveNoFieldControls() {
        for kind in [CreateSessionKind.flash, .bilateral, .colourPulse] {
            let slots = CreateControlSlot.slots(for: kind)
            for fieldOnly in [CreateControlSlot.effect, .tint, .visualSpeed, .strength, .direction] {
                #expect(slots.contains(fieldOnly) == false)
            }
        }
    }

    @Test("Every slot has a non-empty label and icon")
    func labelsAndIcons() {
        for slot in CreateControlSlot.allCases {
            #expect(slot.label.isEmpty == false)
            #expect(slot.systemImage.isEmpty == false)
        }
    }

    @Test("Continuous values drag; discrete ones tap")
    func draggability() {
        for slot in [CreateControlSlot.visualSpeed, .strength, .frequency, .intensity, .warmth] {
            #expect(slot.isDraggable)
        }
        for slot in [CreateControlSlot.effect, .tint, .direction, .duration, .waveform, .binaural] {
            #expect(slot.isDraggable == false)
        }
    }

    @Test("Every slot used by a tray is declared in allCases")
    func everySlotIsDeclared() {
        for kind in CreateSessionKind.allCases {
            for slot in CreateControlSlot.slots(for: kind) {
                #expect(CreateControlSlot.allCases.contains(slot))
            }
        }
    }

    @Test("Every declared slot is reachable from some tray")
    func noOrphanSlots() {
        let used = Set(CreateSessionKind.allCases.flatMap(CreateControlSlot.slots(for:)))
        for slot in CreateControlSlot.allCases {
            #expect(used.contains(slot), "\(slot.rawValue) is declared but no tray shows it")
        }
    }
}
