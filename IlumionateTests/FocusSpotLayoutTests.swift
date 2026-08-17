//
//  FocusSpotLayoutTests.swift
//  IlumionateTests
//
//  The resolver is the only thing standing between a stored preference and
//  spots drawn off the edge of a narrow Mac window, so its clamping is
//  tested harder than its happy path.
//

import CoreGraphics
import Foundation
import Testing

@testable import Ilumionate

@Suite("Focus spot layout")
struct FocusSpotLayoutTests {

    private let field = CGSize(width: 400, height: 900)

    private func settings(
        vertical: Double = 1.0 / 3.0,
        spacing: Double = 180,
        diameter: Double = 48
    ) -> FocusSpotSettings {
        FocusSpotSettings(
            verticalPosition: vertical,
            horizontalSpacing: spacing,
            diameter: diameter
        )
    }

    // MARK: - Anchors

    @Test("Each detent lands at its share of the height", arguments: [
        (1.0 / 3.0, 300.0),
        (0.5, 450.0),
        (2.0 / 3.0, 600.0)
    ])
    func detentsMapToExpectedHeight(vertical: Double, expectedY: Double) throws {
        let resolved = try #require(
            FocusSpotLayout.resolve(settings(vertical: vertical), in: field)
        )

        #expect(abs(resolved.left.y - expectedY) < 0.001)
        #expect(resolved.left.y == resolved.right.y)
    }

    // MARK: - Symmetry

    @Test("Centres are symmetric about the midline and ordered left then right")
    func centresAreSymmetric() throws {
        let resolved = try #require(FocusSpotLayout.resolve(settings(), in: field))

        #expect(resolved.left.x < resolved.right.x)
        #expect(abs((resolved.left.x + resolved.right.x) - field.width) < 0.001)
        #expect(abs((resolved.right.x - resolved.left.x) - 180) < 0.001)
    }

    // MARK: - Clamping

    @Test("A field narrower than the spacing keeps both spots fully inside")
    func narrowFieldClampsSpacing() throws {
        let narrow = CGSize(width: 300, height: 600)
        let resolved = try #require(
            FocusSpotLayout.resolve(settings(spacing: 400), in: narrow)
        )

        #expect(resolved.left.x - resolved.diameter / 2 >= 0)
        #expect(resolved.right.x + resolved.diameter / 2 <= narrow.width)
    }

    @Test("A diameter wider than half the field shrinks so two spots fit")
    func oversizedDiameterShrinks() throws {
        let narrow = CGSize(width: 200, height: 600)
        let resolved = try #require(
            FocusSpotLayout.resolve(settings(diameter: 120), in: narrow)
        )

        #expect(resolved.diameter == 100)
    }

    @Test("Extreme vertical positions keep the whole circle on screen", arguments: [0.1, 0.9])
    func extremeVerticalPositionsStayOnScreen(vertical: Double) throws {
        let short = CGSize(width: 400, height: 120)
        let resolved = try #require(
            FocusSpotLayout.resolve(settings(vertical: vertical), in: short)
        )

        #expect(resolved.left.y - resolved.diameter / 2 >= 0)
        #expect(resolved.left.y + resolved.diameter / 2 <= short.height)
    }

    @Test("A degenerate size resolves to nothing", arguments: [
        CGSize(width: 0, height: 0),
        CGSize(width: 400, height: 0),
        CGSize(width: 0, height: 900)
    ])
    func degenerateSizeReturnsNil(size: CGSize) {
        #expect(FocusSpotLayout.resolve(settings(), in: size) == nil)
    }
}
