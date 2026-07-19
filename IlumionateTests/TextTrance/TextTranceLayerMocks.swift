//  TextTranceLayerMocks.swift
//  IlumionateTests

import Foundation
@testable import Ilumionate

@MainActor
final class MockLightLayer: LightLayerControlling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
final class MockAudioLayer: AudioLayerControlling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastBeatFrequency: Double?
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func syncBeatFrequency(to frequency: Double) { lastBeatFrequency = frequency }
}
