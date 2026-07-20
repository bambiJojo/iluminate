//
//  TabBarClearanceTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

@MainActor
struct TabBarClearanceTests {

    /// Restores the shared metric so tests don't leak state into each other.
    private func withOverlayHeight(_ height: CGFloat, _ body: () -> Void) {
        let previous = BottomChromeMetrics.shared.analysisOverlayHeight
        BottomChromeMetrics.shared.analysisOverlayHeight = height
        body()
        BottomChromeMetrics.shared.analysisOverlayHeight = previous
    }

    @Test("With no analysis overlay the clearance is just the tab bar base")
    func baselineClearance() {
        withOverlayHeight(0) {
            #expect(TranceSpacing.tabBarClearance == TranceSpacing.tabBarBase)
        }
    }

    @Test("An active analysis overlay adds its measured height to the clearance")
    func overlayAddsItsHeight() {
        withOverlayHeight(0) {
            let baseline = TranceSpacing.tabBarClearance
            withOverlayHeight(72) {
                #expect(TranceSpacing.tabBarClearance == baseline + 72 + TranceSpacing.inner)
            }
        }
    }

    @Test("A taller overlay reserves proportionally more space",
          arguments: [48.0, 72.0, 96.0, 140.0])
    func clearanceTracksOverlayHeight(height: Double) {
        withOverlayHeight(0) {
            let baseline = TranceSpacing.tabBarClearance
            withOverlayHeight(CGFloat(height)) {
                #expect(TranceSpacing.tabBarClearance == baseline + CGFloat(height) + TranceSpacing.inner)
            }
        }
    }
}
