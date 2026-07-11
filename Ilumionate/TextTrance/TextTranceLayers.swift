//  TextTranceLayers.swift
//  Ilumionate
//
//  Minimal control surfaces over the existing light and audio engines so the
//  session coordinator depends on protocols (testable with mocks) rather than
//  the concrete CADisplayLink / AVAudioEngine classes.

import Foundation

@MainActor
protocol LightLayerControlling: AnyObject {
    func start()
    func stop()
}

@MainActor
protocol AudioLayerControlling: AnyObject {
    func start()
    func stop()
    func syncBeatFrequency(to frequency: Double)
}

@MainActor
protocol NarrationControlling: AnyObject {
    func start(text: String, speedMultiplier: Double)
    func pause()
    func resume()
    func stop()
}

extension FlashController: LightLayerControlling {}

extension BinauralBeatsEngine: AudioLayerControlling {}
