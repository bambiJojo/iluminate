//  ReaderVisualStrengthTests.swift
//  IlumionateTests
//
//  The Trance tile's drag: strength above the threshold, fully off below it.

import Foundation
import Testing
@testable import Ilumionate

@Suite("Reader visual strength")
struct ReaderVisualStrengthTests {

    @Test("The drag can reach fully off, not merely faint")
    func dragReachesOff() {
        // The visual's own strength range never reaches zero, so the drag range
        // has to start below it for "off" to be reachable at all.
        #expect(ReaderVisualStrength.dragRange.lowerBound == 0)
        #expect(ReaderVisualStrength.dragRange.lowerBound
                < ReaderDisplayPreferences.visualOpacityRange.lowerBound)
    }

    @Test("Dragging to the bottom switches the effect off")
    func bottomSwitchesOff() {
        let resolved = ReaderVisualStrength.resolve(
            draggedValue: 0,
            current: .spiral,
            currentOpacity: 0.5,
            restoring: .spiral
        )
        #expect(resolved.visual == .none)
    }

    @Test("Switching off preserves the strength to come back to")
    func offPreservesStrength() {
        let resolved = ReaderVisualStrength.resolve(
            draggedValue: 0,
            current: .tunnel,
            currentOpacity: 0.62,
            restoring: .tunnel
        )
        #expect(resolved.opacity == 0.62)
    }

    @Test("Dragging back up restores the remembered effect")
    func dragUpRestores() {
        let resolved = ReaderVisualStrength.resolve(
            draggedValue: 0.5,
            current: .none,
            currentOpacity: 0.05,
            restoring: .moire
        )
        #expect(resolved.visual == .moire)
        #expect(resolved.opacity == 0.5)
    }

    @Test("Dragging within range keeps the current effect and takes the value")
    func inRangeKeepsEffect() {
        let resolved = ReaderVisualStrength.resolve(
            draggedValue: 0.4,
            current: .drift,
            currentOpacity: 0.2,
            restoring: .breath
        )
        #expect(resolved.visual == .drift)
        #expect(resolved.opacity == 0.4)
    }

    @Test("The threshold itself is on, not off")
    func thresholdIsOn() {
        let resolved = ReaderVisualStrength.resolve(
            draggedValue: ReaderVisualStrength.offThreshold,
            current: .none,
            currentOpacity: 0,
            restoring: .breath
        )
        #expect(resolved.visual == .breath)
    }

    @Test("Just below the threshold is off")
    func belowThresholdIsOff() {
        let resolved = ReaderVisualStrength.resolve(
            draggedValue: ReaderVisualStrength.offThreshold - 0.001,
            current: .breath,
            currentOpacity: 0.3,
            restoring: .breath
        )
        #expect(resolved.visual == .none)
    }

    @Test("Resolving never yields none while asking for a real strength")
    func neverStrandsOn() {
        for visual in TranceVisual.effects {
            let resolved = ReaderVisualStrength.resolve(
                draggedValue: 0.6,
                current: .none,
                currentOpacity: 0.1,
                restoring: visual
            )
            #expect(resolved.visual != .none)
        }
    }

    // MARK: - Gauge

    @Test("An empty gauge is the off signal")
    func gaugeIsZeroWhenOff() {
        #expect(ReaderVisualStrength.gauge(visual: .none, opacity: 0.8) == 0)
    }

    @Test("Gauge fills across the drag range")
    func gaugeTracksStrength() {
        let low = ReaderVisualStrength.gauge(visual: .breath, opacity: 0.1)
        let high = ReaderVisualStrength.gauge(visual: .breath, opacity: 0.8)
        #expect(low < high)
        #expect(low >= 0)
        #expect(high <= 1)
    }

    @Test("Gauge stays within 0...1 for any strength")
    func gaugeIsClamped() {
        for opacity in [-1.0, 0, 0.05, 0.5, 0.85, 2.0] {
            let gauge = ReaderVisualStrength.gauge(visual: .spiral, opacity: opacity)
            #expect(gauge >= 0 && gauge <= 1)
        }
    }
}
