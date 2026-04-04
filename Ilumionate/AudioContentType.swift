//
//  AudioContentType.swift
//  Ilumionate
//
//  Standalone content-type enum shared between the iOS analysis pipeline and the
//  LumeLabel macOS labeling utility.
//

import Foundation

nonisolated enum AudioContentType: String, Codable, Sendable, CaseIterable {
    case hypnosis
    case meditation
    case music
    case guidedImagery
    case affirmations
    case eroticHypnosis
    case brainwave
    case asmr
    case sleepHypnosis
    case unknown
}
