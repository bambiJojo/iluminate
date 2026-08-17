//
//  VisualTintTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct VisualTintTests {

    // MARK: - Palette

    @Test("Every palette case has a non-empty display name")
    func displayNames() {
        for tint in VisualTint.palette {
            #expect(tint.displayName.isEmpty == false)
        }
    }

    @Test("The palette cases are visually distinct from one another")
    func paletteIsDistinct() {
        let colors = VisualTint.palette.map(\.color)
        #expect(Set(colors).count == colors.count)
    }

    @Test("The default is a palette case, so the picker opens on something selected")
    func defaultIsInThePalette() {
        #expect(VisualTint.palette.contains(VisualTint.default))
    }

    @Test("Only the custom case reports itself as custom")
    func isCustom() {
        for tint in VisualTint.palette {
            #expect(tint.isCustom == false)
        }
        #expect(VisualTint.custom("FF8800").isCustom)
    }

    @Test("Tints round-trip through Codable")
    func codableRoundTrip() throws {
        for tint in VisualTint.palette + [.custom("FF8800")] {
            let data = try JSONEncoder().encode(tint)
            let decoded = try JSONDecoder().decode(VisualTint.self, from: data)
            #expect(decoded == tint)
        }
    }

    // MARK: - Hex parsing

    @Test("A well-formed hex parses with or without its hash")
    func wellFormedHexParses() {
        let withHash = VisualTint.channels(fromHex: "#FF8800")
        let without = VisualTint.channels(fromHex: "FF8800")
        #expect(withHash == without)
        #expect(withHash?.red == 1.0)
        #expect(abs((withHash?.blue ?? 1) - 0) < 0.0001)
    }

    @Test("Malformed hex returns nil so the caller can fall back",
          arguments: ["nonsense", "", "#12", "GGGGGG", "FF88000", "12345"])
    func malformedHexReturnsNil(hex: String) {
        #expect(VisualTint.channels(fromHex: hex) == nil)
    }

    @Test("A malformed hex resolves to the default tint, never to black or clear")
    func malformedHexFallsBack() {
        #expect(VisualTint.custom("nonsense").color == VisualTint.default.color)
        #expect(VisualTint.custom("").color == VisualTint.default.color)
        #expect(VisualTint.custom("#12").color == VisualTint.default.color)
    }

    @Test("A well-formed custom hex is not silently replaced by the default")
    func wellFormedHexIsHonoured() {
        #expect(VisualTint.custom("FF8800").color != VisualTint.default.color)
    }

    // MARK: - Luminance floor

    @Test("A bright colour passes through the floor untouched")
    func brightColourUnchanged() {
        let lifted = VisualTint.lift(red: 0.9, green: 0.9, blue: 0.9)
        #expect(abs(lifted.red - 0.9) < 0.0001)
        #expect(abs(lifted.green - 0.9) < 0.0001)
        #expect(abs(lifted.blue - 0.9) < 0.0001)
    }

    @Test("A near-black colour is lifted to the floor, keeping its hue")
    func darkColourIsLifted() {
        let lifted = VisualTint.lift(red: 0.04, green: 0.0, blue: 0.0)
        #expect(VisualTint.luminance(lifted) >= VisualTint.luminanceFloor - 0.0001)
        // Hue preserved: red still dominates.
        #expect(lifted.red > lifted.green)
        #expect(lifted.red > lifted.blue)
    }

    @Test("Pure black becomes a neutral grey at the floor rather than staying black")
    func pureBlackBecomesGrey() {
        let lifted = VisualTint.lift(red: 0, green: 0, blue: 0)
        #expect(VisualTint.luminance(lifted) >= VisualTint.luminanceFloor - 0.0001)
        #expect(lifted.red == lifted.green)
        #expect(lifted.green == lifted.blue)
    }

    @Test("A saturated but dark colour still reaches the floor")
    func saturatedDarkColourReachesTheFloor() {
        // Pure blue has luminance 0.0722 at full channel value — multiplying it
        // can never reach the floor, because the channel is already maxed. This
        // is the case that makes the lift scale toward white rather than scale
        // the channels.
        let lifted = VisualTint.lift(red: 0, green: 0, blue: 1)
        #expect(VisualTint.luminance(lifted) >= VisualTint.luminanceFloor - 0.0001)
        #expect(lifted.blue >= lifted.red)
    }

    @Test("Lifting never pushes a channel out of range")
    func liftedChannelsStayInRange() {
        for value in [0.0, 0.01, 0.2, 0.5, 0.99, 1.0] {
            let lifted = VisualTint.lift(red: value, green: value * 0.5, blue: 0)
            for channel in [lifted.red, lifted.green, lifted.blue] {
                #expect(channel >= 0)
                #expect(channel <= 1)
            }
        }
    }

    @Test("Out-of-range input is clamped before lifting")
    func outOfRangeInputIsClamped() {
        let lifted = VisualTint.lift(red: 5, green: -3, blue: 0.5)
        #expect(lifted.red <= 1)
        #expect(lifted.green >= 0)
    }

    @Test("Every palette case already clears the floor, so none is lifted")
    func paletteClearsTheFloor() {
        // If a curated colour needed lifting, the palette and the floor would
        // disagree about what "visible" means.
        for tint in VisualTint.palette {
            #expect(tint.isCustom == false)
        }
        #expect(VisualTint.luminanceFloor > 0)
        #expect(VisualTint.luminanceFloor < 1)
    }
}
