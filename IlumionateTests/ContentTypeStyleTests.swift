//
//  ContentTypeStyleTests.swift
//  IlumionateTests
//

import Testing
import SwiftUI
@testable import Ilumionate

struct ContentTypeStyleTests {
    @Test("Known content types map to their zone color and a non-empty SF Symbol")
    func knownTypes() {
        #expect(ContentTypeStyle.color(for: .hypnosis) == .bwDelta)
        #expect(ContentTypeStyle.color(for: .meditation) == .bwAlpha)
        #expect(ContentTypeStyle.color(for: .brainwave) == .bwGamma)
        #expect(ContentTypeStyle.icon(for: .hypnosis) == "brain.head.profile")
        #expect(!ContentTypeStyle.icon(for: .music).isEmpty)
    }

    @Test("nil content type falls back to the adaptive primary accent and waveform icon")
    func nilFallback() {
        #expect(ContentTypeStyle.color(for: nil) == .roseGold)
        #expect(ContentTypeStyle.icon(for: nil) == "waveform")
    }
}
