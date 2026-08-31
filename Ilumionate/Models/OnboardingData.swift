//
//  OnboardingData.swift
//  LumeSync
//
//  Created by Claude on Context

import Foundation
import SwiftUI

/// Pre-defined options for the "Why did you download?" questionnaire
enum OnboardingGoal: String, CaseIterable, Identifiable {
    case relaxation = "Gentle Wind-down"
    case sleep = "Night Session"
    case focus = "Focused Time"
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
        case .relaxation: return "Set a Gentle Pace"
        case .sleep: return "Settle In for the Night"
        case .focus: return "Choose an Active Rhythm"
        case .meditation: return "Follow the Hypnosis Arc"
        case .curious: return "Discover the Mind Machine"
        }
    }

    var personalizedResponseDescription: String {
        switch self {
        case .relaxation:
            return "Pair your chosen audio with gently pulsing light, warm colours, and slow transitions that you can adjust at any time."
        case .sleep:
            return "Choose slower light patterns and warm colours for a quiet, low-intensity session while you settle in for the night."
        case .focus:
            return "Choose brighter, faster patterns when you want an active visual rhythm for a reading or listening session."
        case .meditation:
            return "The Audio Analyzer maps the structure of your hypnosis audio to synchronized light changes that follow its pacing."
        case .curious:
            return "Explore adjustable flashing lights, colour pulses, bilateral patterns, and audio-synchronized sessions."
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
