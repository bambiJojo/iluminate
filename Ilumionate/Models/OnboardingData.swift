//
//  OnboardingData.swift
//  LumeSync
//
//  Created by Claude on Context

import Foundation
import SwiftUI

/// Pre-defined options for the "Why did you download?" questionnaire
enum OnboardingGoal: String, CaseIterable, Identifiable {
    case relaxation = "Deep Relaxation"
    case sleep = "Better Sleep"
    case focus = "Focus & Productivity"
    case meditation = "Meditation & Trance"
    case curious = "Just Curious"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .relaxation: return "wind"
        case .sleep: return "moon.zzz.fill"
        case .focus: return "target"
        case .meditation: return "brain.head.profile"
        case .curious: return "eye.circle.fill"
        }
    }

    var personalizedResponseTitle: String {
        switch self {
        case .relaxation: return "Unwind Effortlessly"
        case .sleep: return "Drift Into Sleep"
        case .focus: return "Lock In"
        case .meditation: return "Enter the Trance"
        case .curious: return "Discover the Mind Machine"
        }
    }

    var personalizedResponseDescription: String {
        switch self {
        case .relaxation:
            return "LumeSync's brainwave entrainment gently slows your mind down, washing away the stress of the day with pulsing lights."
        case .sleep:
            return "By syncing your brainwaves to Delta frequencies, the Mind Machine guides you naturally into a deep, restorative sleep."
        case .focus:
            return "Gamma and Beta frequency light pulses stimulate your mind, cutting through brain fog to help you achieve laser focus."
        case .meditation:
            return "Our built-in Audio Analyzer syncs light pulses perfectly with your hypnosis audio, guiding you effortlessly into deep trance states."
        case .curious:
            return "Experience the power of brainwave entrainment. LumeSync uses flashing lights to synchronize your brain, safely guiding your mental state."
        }
    }
}
