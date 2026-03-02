//
//  LightScorePlayer.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/9/26.
//

import Foundation
import Observation
import QuartzCore

/// Interpolates between LightMoments to provide smooth control curves.
///
/// This player doesn't step through discrete points — it continuously
/// interpolates frequency, intensity, and other parameters based on
/// the current playback time.
///
/// The engine queries this player each frame to get the target state,
/// which is then smoothly ramped to by the LightEngine.
@Observable
@MainActor
class LightScorePlayer {

    // MARK: - Public State

    /// The loaded session being played
    let session: LightSession

    /// Current playback time in seconds from session start
    private(set) var currentTime: Double = 0.0

    /// Whether playback is active
    private(set) var isPlaying: Bool = false

    /// Whether the session has completed
    private(set) var isComplete: Bool = false

    // MARK: - Private State

    /// Sorted moments for efficient lookup
    private let moments: [LightMoment]

    /// Start time reference (CACurrentMediaTime)
    private var startTime: CFTimeInterval = 0.0

    /// Performance optimization: cached last search index
    private var lastSearchIndex: Int = 0

    /// Performance optimization: cached last interpolation result
    private var cachedState: (time: Double, state: SessionState)?

    // MARK: - Initialization

    init(session: LightSession) {
        self.session = session
        self.moments = session.light_score.sorted { $0.time < $1.time }
    }

    // MARK: - Playback Control

    /// Start or resume playback
    func play() {
        guard !isPlaying else { return }
        startTime = CACurrentMediaTime() - currentTime
        isPlaying = true
        isComplete = false
    }

    /// Pause playback at current position
    func pause() {
        guard isPlaying else { return }
        isPlaying = false
    }

    /// Stop and reset to beginning
    func stop() {
        isPlaying = false
        currentTime = 0.0
        startTime = 0.0
        isComplete = false
    }

    /// Seek to a specific time
    func seek(to time: Double) {
        let clampedTime = max(0.0, min(time, session.duration_sec))
        currentTime = clampedTime
        if isPlaying {
            startTime = CACurrentMediaTime() - clampedTime
        }
        isComplete = clampedTime >= session.duration_sec
    }

    // MARK: - State Query

    /// Update the current time based on real clock time.
    /// Call this from your CADisplayLink tick.
    func updateTime() {
        guard isPlaying else { return }

        let elapsed = CACurrentMediaTime() - startTime
        currentTime = elapsed

        // Check for session completion
        if currentTime >= session.duration_sec {
            currentTime = session.duration_sec
            isPlaying = false
            isComplete = true
        }
    }

    /// Returns the interpolated state at the current playback time.
    /// This is what the LightEngine should target.
    func currentState() -> SessionState {
        return state(at: currentTime)
    }

    /// Returns the interpolated state at a specific time.
    /// Used internally and for preview/scrubbing.
    func state(at time: Double) -> SessionState {
        // Handle edge cases
        guard !moments.isEmpty else {
            return SessionState(
                frequency: 10.0,
                intensity: 0.5,
                waveform: .sine,
                bilateral: false,
                rampDuration: nil,
                bilateralTransitionDuration: nil,
                colorTemperature: nil
            )
        }

        // Before first moment - use first moment's values
        if time <= moments.first!.time {
            let first = moments.first!
            return SessionState(
                frequency: first.frequency,
                intensity: first.intensity,
                waveform: first.waveform.toWaveform,
                bilateral: first.bilateral ?? false,
                rampDuration: first.ramp_duration,
                bilateralTransitionDuration: first.bilateral_transition_duration,
                colorTemperature: first.color_temperature
            )
        }

        // After last moment - use last moment's values
        if time >= moments.last!.time {
            let last = moments.last!
            return SessionState(
                frequency: last.frequency,
                intensity: last.intensity,
                waveform: last.waveform.toWaveform,
                bilateral: last.bilateral ?? false,
                rampDuration: last.ramp_duration,
                bilateralTransitionDuration: last.bilateral_transition_duration,
                colorTemperature: last.color_temperature
            )
        }

        // Performance optimization: Check cache first
        if let cached = cachedState, abs(cached.time - time) < 0.001 {
            return cached.state
        }

        // Find the two moments we're between using optimized binary search
        let nextIndex = findMomentIndex(for: time)

        guard nextIndex > 0 && nextIndex < moments.count else {
            // Fallback to first or last moment
            let moment = nextIndex <= 0 ? moments.first! : moments.last!
            let state = SessionState(
                frequency: moment.frequency,
                intensity: moment.intensity,
                waveform: moment.waveform.toWaveform,
                bilateral: moment.bilateral ?? false,
                rampDuration: moment.ramp_duration,
                bilateralTransitionDuration: moment.bilateral_transition_duration,
                colorTemperature: moment.color_temperature
            )
            cachedState = (time, state)
            return state
        }

        let prev = moments[nextIndex - 1]
        let next = moments[nextIndex]

        // Calculate interpolation factor (0.0 at prev, 1.0 at next)
        let duration = next.time - prev.time
        let alpha = duration > 0 ? (time - prev.time) / duration : 0.0

        // Linear interpolation for frequency and intensity
        let freq = prev.frequency + (next.frequency - prev.frequency) * alpha
        let inten = prev.intensity + (next.intensity - prev.intensity) * alpha

        // Interpolate color temperature if both moments specify it
        let colorTemp: Double?
        if let prevTemp = prev.color_temperature, let nextTemp = next.color_temperature {
            colorTemp = prevTemp + (nextTemp - prevTemp) * alpha
        } else {
            // Use whichever is available, preferring next
            colorTemp = next.color_temperature ?? prev.color_temperature
        }

        // Use the previous moment's waveform and settings until we reach the next one
        // This prevents jarring mid-transition waveform changes
        let state = SessionState(
            frequency: freq,
            intensity: inten,
            waveform: prev.waveform.toWaveform,
            bilateral: prev.bilateral ?? false,
            rampDuration: next.ramp_duration,
            bilateralTransitionDuration: next.bilateral_transition_duration,
            colorTemperature: colorTemp
        )

        // Cache the result for next frame
        cachedState = (time, state)
        return state
    }

    // MARK: - Performance Optimizations

    /// Optimized binary search to find moment index for given time
    /// Uses cached last index as starting hint for better performance
    private func findMomentIndex(for time: Double) -> Int {
        guard !moments.isEmpty else { return 0 }

        // Start search from cached index as hint
        var startIndex = max(0, min(lastSearchIndex, moments.count - 1))

        // Quick check: if time is close to last search, scan nearby
        if startIndex < moments.count {
            let currentMoment = moments[startIndex]

            // If time is very close to cached position, scan linearly (faster than binary search)
            if abs(currentMoment.time - time) < 5.0 { // 5 second window
                if time >= currentMoment.time {
                    // Scan forward
                    while startIndex < moments.count - 1 && moments[startIndex + 1].time <= time {
                        startIndex += 1
                    }
                    lastSearchIndex = startIndex
                    return startIndex + 1
                } else {
                    // Scan backward
                    while startIndex > 0 && moments[startIndex].time > time {
                        startIndex -= 1
                    }
                    lastSearchIndex = startIndex
                    return startIndex + 1
                }
            }
        }

        // Use binary search for distant times
        var left = 0
        var right = moments.count - 1

        while left <= right {
            let mid = (left + right) / 2
            let midTime = moments[mid].time

            if midTime < time {
                left = mid + 1
            } else if midTime > time {
                right = mid - 1
            } else {
                // Exact match
                lastSearchIndex = mid
                return mid + 1
            }
        }

        // Cache the result
        lastSearchIndex = left
        return left
    }

    // MARK: - Timeline Info

    /// Get the moment index that is currently active (or about to be)
    func currentMomentIndex() -> Int? {
        guard !moments.isEmpty else { return nil }

        // Find the last moment at or before current time
        if let index = moments.lastIndex(where: { $0.time <= currentTime }) {
            return index
        }

        // We're before the first moment
        return nil
    }

    /// Progress through the session (0.0 to 1.0)
    var progress: Double {
        guard session.duration_sec > 0 else { return 0.0 }
        return min(1.0, currentTime / session.duration_sec)
    }
}

// MARK: - Session State

/// The interpolated target state for the light engine at a specific time
struct SessionState {
    let frequency: Double
    let intensity: Double
    let waveform: Waveform
    let bilateral: Bool
    let rampDuration: Double?
    let bilateralTransitionDuration: Double?
    let colorTemperature: Double?  // Kelvin: 2000-6500
}
