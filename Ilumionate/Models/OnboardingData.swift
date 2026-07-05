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

    /// Session-generation preferences to apply at onboarding completion so the
    /// user's very first generated session already reflects their stated goal
    /// (smart defaults). Returns `nil` for goals with no strong prior — those
    /// keep the app's neutral defaults, which the user can still tune later.
    var recommendedPreferenceSeed: OnboardingPreferenceSeed? {
        switch self {
        case .relaxation:
            return OnboardingPreferenceSeed(
                frequencyProfile: .conservative,
                transitionStyle: .fluid,
                colorTempMode: .warm,
                intensityMultiplier: 0.9,
                bilateralMode: false,
                contentHint: .meditation
            )
        case .sleep:
            return OnboardingPreferenceSeed(
                frequencyProfile: .conservative,
                transitionStyle: .fluid,
                colorTempMode: .warm,
                intensityMultiplier: 0.75,
                bilateralMode: false,
                contentHint: .sleepAid
            )
        case .focus:
            return OnboardingPreferenceSeed(
                frequencyProfile: .standard,
                transitionStyle: .standard,
                colorTempMode: .cool,
                intensityMultiplier: 1.0,
                bilateralMode: false,
                contentHint: .none
            )
        case .meditation:
            return OnboardingPreferenceSeed(
                frequencyProfile: .deep,
                transitionStyle: .fluid,
                colorTempMode: .warm,
                intensityMultiplier: 1.0,
                bilateralMode: true,
                contentHint: .hypnosis
            )
        case .curious:
            return nil
        }
    }
}

/// A bundle of session-generation preferences seeded from the onboarding goal.
struct OnboardingPreferenceSeed {
    let frequencyProfile: FrequencyProfile
    let transitionStyle: TransitionStyle
    let colorTempMode: ColorTempMode
    let intensityMultiplier: Double
    let bilateralMode: Bool
    let contentHint: ContentHint
}
