//
//  SessionValidationExample.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation

/// Example code showing how to validate and analyze sessions.
/// This can be run from a command-line tool or in Xcode.
@MainActor
class SessionValidationExample {

    /// Load and validate a session from a JSON file
    static func validateSessionFile(at path: String) {
        print("\n" + String(repeating: "=", count: 60))
        print("VALIDATING SESSION FILE")
        print(String(repeating: "=", count: 60))
        print("File:", path)
        print()

        // Load JSON
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("❌ Failed to load file")
            return
        }

        // Decode session
        let decoder = JSONDecoder()
        guard let session = try? decoder.decode(LightSession.self, from: data) else {
            print("❌ Failed to decode JSON")
            return
        }

        print("✅ Session loaded successfully")
        print("   Name: \(session.displayName)")
        print("   Duration: \(session.durationFormatted)")
        print("   Moments: \(session.light_score.count)")
        print()

        // Validate
        let validation = SessionDiagnostics.validateSession(session)
        print(validation.summary)
        print()

        if !validation.errors.isEmpty {
            print("ERRORS:")
            for error in validation.errors {
                print("  ❌", error)
            }
            print()
        }

        if !validation.warnings.isEmpty {
            print("WARNINGS:")
            for warning in validation.warnings {
                print("  ⚠️", warning)
            }
            print()
        }

        // Analyze
        let analysis = SessionDiagnostics.analyzeSession(session)
        print("ANALYSIS:")
        print("  Effectiveness: \(analysis.estimatedEntrainmentEffectiveness.emoji) \(analysis.estimatedEntrainmentEffectiveness.rawValue)")
        print("  Frequency range: \(String(format: "%.1f", analysis.frequencyRange.min)) - \(String(format: "%.1f", analysis.frequencyRange.max)) Hz")
        print("  Average frequency: \(String(format: "%.1f", analysis.averageFrequency)) Hz")
        print("  Intensity range: \(String(format: "%.2f", analysis.intensityRange.min)) - \(String(format: "%.2f", analysis.intensityRange.max))")
        print("  Average intensity: \(String(format: "%.2f", analysis.averageIntensity))")
        print("  Bilateral mode: \(analysis.hasBilateral ? "Yes" : "No")")
        print("  Color temperature: \(analysis.hasColorTemperature ? "Yes" : "No")")
        print("  Custom ramps: \(analysis.hasCustomRamps ? "Yes" : "No")")
        print()

        if !analysis.suggestions.isEmpty {
            print("SUGGESTIONS:")
            for suggestion in analysis.suggestions {
                print("  💡", suggestion)
            }
            print()
        }

        // Log details
        print(SessionDiagnostics.logSessionDetails(session))

        print(String(repeating: "=", count: 60))
        print()
    }

    /// Example: Validate the included example session
    static func validateExampleSession() {
        // Create a well-designed session
        let session = LightSession(
            session_name: "Deep Focus - 20 Minutes",
            duration_sec: 1200,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.3, waveform: .sine, ramp_duration: 5.0, bilateral: false, color_temperature: 3500),
                LightMoment(time: 60, frequency: 12, intensity: 0.5, waveform: .sine, ramp_duration: 8.0, bilateral: false, color_temperature: 4000),
                LightMoment(time: 180, frequency: 14, intensity: 0.6, waveform: .softPulse, ramp_duration: 10.0, bilateral: true, bilateral_transition_duration: 6.0, color_temperature: 4500),
                LightMoment(time: 360, frequency: 15, intensity: 0.7, waveform: .softPulse, ramp_duration: 5.0, bilateral: true, color_temperature: 5000),
                LightMoment(time: 540, frequency: 16, intensity: 0.75, waveform: .noiseModulatedSine, ramp_duration: 8.0, bilateral: true, color_temperature: 5500),
                LightMoment(time: 720, frequency: 15, intensity: 0.7, waveform: .softPulse, ramp_duration: 5.0, bilateral: true, color_temperature: 5000),
                LightMoment(time: 900, frequency: 13, intensity: 0.6, waveform: .sine, ramp_duration: 8.0, bilateral: true, color_temperature: 4500),
                LightMoment(time: 1080, frequency: 11, intensity: 0.4, waveform: .sine, ramp_duration: 10.0, bilateral: false, bilateral_transition_duration: 8.0, color_temperature: 4000),
                LightMoment(time: 1200, frequency: 10, intensity: 0.2, waveform: .sine, ramp_duration: 8.0, bilateral: false, color_temperature: 3500)
            ]
        )

        print("\n" + String(repeating: "=", count: 60))
        print("VALIDATING EXAMPLE SESSION")
        print(String(repeating: "=", count: 60))
        print()

        // Validate
        let validation = SessionDiagnostics.validateSession(session)
        print(validation.summary)
        print()

        if !validation.errors.isEmpty {
            print("ERRORS:")
            for error in validation.errors {
                print("  ❌", error)
            }
            print()
        }

        if !validation.warnings.isEmpty {
            print("WARNINGS:")
            for warning in validation.warnings {
                print("  ⚠️", warning)
            }
            print()
        }

        // Analyze
        let analysis = SessionDiagnostics.analyzeSession(session)
        print("ANALYSIS:")
        print("  Effectiveness: \(analysis.estimatedEntrainmentEffectiveness.emoji) \(analysis.estimatedEntrainmentEffectiveness.rawValue)")
        print("  Frequency: \(String(format: "%.1f", analysis.frequencyRange.min))-\(String(format: "%.1f", analysis.frequencyRange.max)) Hz (avg: \(String(format: "%.1f", analysis.averageFrequency)))")
        print("  Intensity: \(String(format: "%.2f", analysis.intensityRange.min))-\(String(format: "%.2f", analysis.intensityRange.max)) (avg: \(String(format: "%.2f", analysis.averageIntensity)))")
        print("  Features: Bilateral=\(analysis.hasBilateral), ColorTemp=\(analysis.hasColorTemperature), CustomRamps=\(analysis.hasCustomRamps)")
        print()

        if !analysis.suggestions.isEmpty {
            print("SUGGESTIONS:")
            for suggestion in analysis.suggestions {
                print("  💡", suggestion)
            }
            print()
        } else {
            print("✨ No suggestions - session is well optimized!")
            print()
        }

        print(String(repeating: "=", count: 60))
        print()
    }

    /// Example: Test a problematic session that should trigger warnings
    static func validateProblematicSession() {
        let session = LightSession(
            session_name: "Problematic Session (Demo)",
            duration_sec: 30,
            light_score: [
                LightMoment(time: 0, frequency: 5, intensity: 0.1, waveform: .sine),
                LightMoment(time: 5, frequency: 50, intensity: 0.95, waveform: .triangle), // Rapid change + high frequency
                LightMoment(time: 10, frequency: 3, intensity: 0.05, waveform: .sine), // Another rapid change
                LightMoment(time: 15, frequency: 60, intensity: 1.0, waveform: .triangle) // Near seizure threshold
            ]
        )

        print("\n" + String(repeating: "=", count: 60))
        print("VALIDATING PROBLEMATIC SESSION (FOR TESTING)")
        print(String(repeating: "=", count: 60))
        print()

        let validation = SessionDiagnostics.validateSession(session)
        print(validation.summary)
        print()

        if !validation.errors.isEmpty {
            print("ERRORS:")
            for error in validation.errors {
                print("  ❌", error)
            }
            print()
        }

        if !validation.warnings.isEmpty {
            print("WARNINGS:")
            for warning in validation.warnings {
                print("  ⚠️", warning)
            }
            print()
        }

        let analysis = SessionDiagnostics.analyzeSession(session)
        print("Effectiveness: \(analysis.estimatedEntrainmentEffectiveness.emoji) \(analysis.estimatedEntrainmentEffectiveness.rawValue)")

        if !analysis.suggestions.isEmpty {
            print("\nSUGGESTIONS:")
            for suggestion in analysis.suggestions {
                print("  💡", suggestion)
            }
        }

        print()
        print(String(repeating: "=", count: 60))
        print()
    }

    /// Run all validation examples
    static func runAllExamples() {
        print("\n🧪 RUNNING SESSION VALIDATION EXAMPLES\n")

        validateExampleSession()
        validateProblematicSession()

        print("✅ All validation examples complete!\n")
    }
}

// MARK: - Usage Example

/*
 To use this in your app:
 
 // In a view or app startup:
 Task { @MainActor in
     SessionValidationExample.runAllExamples()
 }
 
 // Or validate a specific file:
 Task { @MainActor in
     SessionValidationExample.validateSessionFile(at: "/path/to/session.json")
 }
 
 // Or in a test:
 @Test("Validate example session")
 @MainActor
 func validateExampleSession() {
     SessionValidationExample.validateExampleSession()
 }
 */
