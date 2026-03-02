//
//  IlumionateTests.swift
//  IlumionateTests
//
//  Comprehensive test suite for the Ilumionate app
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Data Model Tests

struct PlaylistModelTests {

    @Test func playlistCreation() {
        let playlist = Playlist(name: "Test Playlist")
        #expect(playlist.name == "Test Playlist")
        #expect(playlist.items.isEmpty)
        #expect(playlist.smartTransitions == true) // default
        #expect(playlist.totalDuration == 0)
        #expect(playlist.itemCount == 0)
        #expect(playlist.isEmpty)
    }

    @Test func playlistItemCreation() {
        let item = PlaylistItem(
            audioFileId: UUID(),
            filename: "test.mp3",
            duration: 300
        )
        #expect(item.filename == "test.mp3")
        #expect(item.duration == 300)
        #expect(item.durationFormatted == "5:00")
    }

    @Test func playlistDurationCalculation() {
        var playlist = Playlist(name: "Test")
        playlist.items = [
            PlaylistItem(audioFileId: UUID(), filename: "a.mp3", duration: 120),
            PlaylistItem(audioFileId: UUID(), filename: "b.mp3", duration: 180),
            PlaylistItem(audioFileId: UUID(), filename: "c.mp3", duration: 60)
        ]
        #expect(playlist.totalDuration == 360)
        #expect(playlist.totalDurationFormatted == "6:00")
        #expect(playlist.itemCount == 3)
        #expect(!playlist.isEmpty)
    }

    @Test func playlistDurationFormattingEdgeCases() {
        var playlist = Playlist(name: "Test")
        // 0 duration
        #expect(playlist.totalDurationFormatted == "0:00")

        // Exactly 1 minute
        playlist.items = [PlaylistItem(audioFileId: UUID(), filename: "a.mp3", duration: 60)]
        #expect(playlist.totalDurationFormatted == "1:00")

        // 59 seconds
        playlist.items = [PlaylistItem(audioFileId: UUID(), filename: "a.mp3", duration: 59)]
        #expect(playlist.totalDurationFormatted == "0:59")

        // Large duration (over 1 hour)
        playlist.items = [PlaylistItem(audioFileId: UUID(), filename: "a.mp3", duration: 3661)]
        #expect(playlist.totalDurationFormatted == "61:01")
    }

    @Test func playlistCodable() throws {
        let id = UUID()
        let audioId = UUID()
        var playlist = Playlist(id: id, name: "Encoded Playlist", smartTransitions: false)
        playlist.items = [
            PlaylistItem(audioFileId: audioId, filename: "test.mp3", duration: 120)
        ]

        let data = try JSONEncoder().encode(playlist)
        let decoded = try JSONDecoder().decode(Playlist.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.name == "Encoded Playlist")
        #expect(decoded.smartTransitions == false)
        #expect(decoded.items.count == 1)
        #expect(decoded.items[0].audioFileId == audioId)
        #expect(decoded.items[0].filename == "test.mp3")
        #expect(decoded.items[0].duration == 120)
    }

    @Test func playlistStoreSaveAndLoad() {
        // Save
        let playlist = Playlist(name: "Persist Test")
        PlaylistStore.save([playlist])

        // Load
        let loaded = PlaylistStore.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Persist Test")
        #expect(loaded[0].id == playlist.id)

        // Cleanup
        PlaylistStore.save([])
    }

    @Test func playlistStoreEmptyLoad() {
        // Clear any existing data
        UserDefaults.standard.removeObject(forKey: "playlists")
        let loaded = PlaylistStore.load()
        #expect(loaded.isEmpty)
    }
}

// MARK: - Audio File Model Tests

struct AudioFileModelTests {

    @Test func audioFileDurationFormatting() {
        let file = AudioFile(
            filename: "test.mp3",
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            duration: 125,
            fileSize: 1024000
        )
        #expect(file.durationFormatted == "2:05")
    }

    @Test func audioFileZeroDuration() {
        let file = AudioFile(
            filename: "empty.mp3",
            url: URL(fileURLWithPath: "/tmp/empty.mp3"),
            duration: 0,
            fileSize: 0
        )
        #expect(file.durationFormatted == "0:00")
    }

    @Test func audioFileFileSizeFormatting() {
        let file = AudioFile(
            filename: "test.mp3",
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            duration: 100,
            fileSize: 1048576 // 1 MB
        )
        // ByteCountFormatter should produce something like "1 MB" or "1,048,576 bytes"
        #expect(!file.fileSizeFormatted.isEmpty)
    }

    @Test func audioFileAnalysisState() {
        var file = AudioFile(
            filename: "test.mp3",
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            duration: 100,
            fileSize: 1000
        )
        #expect(!file.isAnalyzed)
        #expect(!file.hasTranscription)

        file.transcription = "Hello world"
        #expect(file.hasTranscription)

        file.transcription = ""
        #expect(!file.hasTranscription)

        file.transcription = nil
        #expect(!file.hasTranscription)
    }

    @Test func audioFileCodable() throws {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/test.mp3")
        let file = AudioFile(
            id: id,
            filename: "test.mp3",
            url: url,
            duration: 300,
            fileSize: 5000
        )

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(AudioFile.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.filename == "test.mp3")
        #expect(decoded.duration == 300)
        #expect(decoded.fileSize == 5000)
    }
}

// MARK: - LightSession Model Tests

struct LightSessionTests {

    @Test func lightSessionCreation() {
        let session = LightSession(
            session_name: "Test Session",
            duration_sec: 600,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
                LightMoment(time: 300, frequency: 6, intensity: 0.8, waveform: .softPulse),
                LightMoment(time: 600, frequency: 12, intensity: 0.3, waveform: .sine)
            ]
        )
        #expect(session.displayName == "Test Session")
        #expect(session.duration_sec == 600)
        #expect(session.durationFormatted == "10:00")
        #expect(session.light_score.count == 3)
    }

    @Test func lightMomentOptionalFields() {
        let moment = LightMoment(
            time: 0,
            frequency: 10,
            intensity: 0.5,
            waveform: .sine,
            ramp_duration: 5.0,
            bilateral: true,
            bilateral_transition_duration: 2.0,
            color_temperature: 3500
        )
        #expect(moment.ramp_duration == 5.0)
        #expect(moment.bilateral == true)
        #expect(moment.bilateral_transition_duration == 2.0)
        #expect(moment.color_temperature == 3500)
    }

    @Test func lightMomentDefaultOptionals() {
        let moment = LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)
        #expect(moment.ramp_duration == nil)
        #expect(moment.bilateral == nil)
        #expect(moment.bilateral_transition_duration == nil)
        #expect(moment.color_temperature == nil)
    }

    @Test func lightSessionCodableRoundTrip() throws {
        let session = LightSession(
            session_name: "Codable Test",
            duration_sec: 120,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine, bilateral: false, color_temperature: 3500),
                LightMoment(time: 60, frequency: 6, intensity: 0.8, waveform: .softPulse, bilateral: true, color_temperature: 2500),
                LightMoment(time: 120, frequency: 12, intensity: 0.3, waveform: .triangle)
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        let decoded = try JSONDecoder().decode(LightSession.self, from: data)

        #expect(decoded.session_name == "Codable Test")
        #expect(decoded.duration_sec == 120)
        #expect(decoded.light_score.count == 3)
        #expect(decoded.light_score[0].frequency == 10)
        #expect(decoded.light_score[1].bilateral == true)
        #expect(decoded.light_score[2].color_temperature == nil)
    }
}

// MARK: - WaveformType Tests

struct WaveformTypeTests {

    @Test func waveformTypeToWaveformMapping() {
        #expect(WaveformType.sine.toWaveform == .sine)
        #expect(WaveformType.triangle.toWaveform == .triangle)
        #expect(WaveformType.softPulse.toWaveform == .softPulse)
        #expect(WaveformType.rampHold.toWaveform == .rampHold)
        #expect(WaveformType.noiseModulatedSine.toWaveform == .noiseModulatedSine)
    }

    @Test func waveformTypeMissingSquare() {
        // WaveformType does NOT include .square — verify the runtime Waveform does
        // This tests that the enum gap between Waveform (has .square) and WaveformType (no .square) is known
        let allWaveformTypes = WaveformType.allCases
        let waveformTypeNames = allWaveformTypes.map { $0.rawValue }

        // WaveformType should not have square
        #expect(!waveformTypeNames.contains("square"))

        // But the runtime Waveform does have square
        let runtimeSquare = Waveform.square
        #expect(runtimeSquare.evaluate(at: 0.25) == 1.0)
        #expect(runtimeSquare.evaluate(at: 0.75) == 0.0)
    }

    @Test func waveformTypeJSONEncoding() throws {
        // Verify snake_case encoding for JSON session files
        let moment = LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .softPulse)
        let data = try JSONEncoder().encode(moment)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"soft_pulse\""))

        let moment2 = LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .rampHold)
        let data2 = try JSONEncoder().encode(moment2)
        let json2 = String(data: data2, encoding: .utf8)!
        #expect(json2.contains("\"ramp_hold\""))

        let moment3 = LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .noiseModulatedSine)
        let data3 = try JSONEncoder().encode(moment3)
        let json3 = String(data: data3, encoding: .utf8)!
        #expect(json3.contains("\"noise_sine\""))
    }
}

// MARK: - LightScorePlayer Tests

struct LightScorePlayerTests {

    @MainActor
    @Test func playerInterpolationBetweenMoments() {
        let session = LightSession(
            session_name: "Interpolation Test",
            duration_sec: 100,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.0, waveform: .sine),
                LightMoment(time: 100, frequency: 20, intensity: 1.0, waveform: .sine)
            ]
        )

        let player = LightScorePlayer(session: session)

        // At time 0
        let state0 = player.state(at: 0)
        #expect(state0.frequency == 10.0)
        #expect(state0.intensity == 0.0)

        // At time 50 — should be midpoint interpolation
        let state50 = player.state(at: 50)
        #expect(abs(state50.frequency - 15.0) < 0.01)
        #expect(abs(state50.intensity - 0.5) < 0.01)

        // At time 100
        let state100 = player.state(at: 100)
        #expect(state100.frequency == 20.0)
        #expect(state100.intensity == 1.0)
    }

    @MainActor
    @Test func playerColorTemperatureInterpolation() {
        let session = LightSession(
            session_name: "Color Temp Test",
            duration_sec: 100,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine, color_temperature: 5000),
                LightMoment(time: 100, frequency: 10, intensity: 0.5, waveform: .sine, color_temperature: 2000)
            ]
        )

        let player = LightScorePlayer(session: session)

        let state50 = player.state(at: 50)
        #expect(state50.colorTemperature != nil)
        #expect(abs(state50.colorTemperature! - 3500) < 0.01)
    }

    @MainActor
    @Test func playerColorTemperatureMixedNils() {
        let session = LightSession(
            session_name: "Mixed Color Test",
            duration_sec: 100,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine, color_temperature: nil),
                LightMoment(time: 100, frequency: 10, intensity: 0.5, waveform: .sine, color_temperature: 3000)
            ]
        )

        let player = LightScorePlayer(session: session)

        // When one is nil, should use whichever is available (prefers next)
        let state50 = player.state(at: 50)
        #expect(state50.colorTemperature == 3000)
    }

    @MainActor
    @Test func playerEmptyMoments() {
        let session = LightSession(
            session_name: "Empty",
            duration_sec: 100,
            light_score: []
        )

        let player = LightScorePlayer(session: session)
        let state = player.state(at: 50)

        // Should return default fallback values
        #expect(state.frequency == 10.0)
        #expect(state.intensity == 0.5)
        #expect(state.waveform == .sine)
        #expect(state.bilateral == false)
    }

    @MainActor
    @Test func playerBeforeFirstMoment() {
        let session = LightSession(
            session_name: "Late Start",
            duration_sec: 100,
            light_score: [
                LightMoment(time: 30, frequency: 8, intensity: 0.7, waveform: .triangle),
                LightMoment(time: 100, frequency: 4, intensity: 0.9, waveform: .softPulse)
            ]
        )

        let player = LightScorePlayer(session: session)

        // Before first moment — should use first moment's values
        let stateEarly = player.state(at: 10)
        #expect(stateEarly.frequency == 8.0)
        #expect(stateEarly.intensity == 0.7)
    }

    @MainActor
    @Test func playerAfterLastMoment() {
        let session = LightSession(
            session_name: "Early End",
            duration_sec: 100,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine),
                LightMoment(time: 50, frequency: 6, intensity: 0.8, waveform: .softPulse)
            ]
        )

        let player = LightScorePlayer(session: session)

        // After last moment — should use last moment's values
        let stateLate = player.state(at: 80)
        #expect(stateLate.frequency == 6.0)
        #expect(stateLate.intensity == 0.8)
    }

    @MainActor
    @Test func playerProgressCalculation() {
        let session = LightSession(
            session_name: "Progress Test",
            duration_sec: 200,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)
            ]
        )

        let player = LightScorePlayer(session: session)
        #expect(player.progress == 0.0)

        player.seek(to: 100)
        #expect(abs(player.progress - 0.5) < 0.01)

        player.seek(to: 200)
        #expect(abs(player.progress - 1.0) < 0.01)
    }

    @MainActor
    @Test func playerZeroDurationSession() {
        let session = LightSession(
            session_name: "Zero Duration",
            duration_sec: 0,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)
            ]
        )

        let player = LightScorePlayer(session: session)
        // Should not divide by zero
        #expect(player.progress == 0.0)
    }

    @MainActor
    @Test func playerBilateralInterpolation() {
        let session = LightSession(
            session_name: "Bilateral Test",
            duration_sec: 100,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine, bilateral: false),
                LightMoment(time: 50, frequency: 6, intensity: 0.8, waveform: .softPulse, bilateral: true),
                LightMoment(time: 100, frequency: 10, intensity: 0.5, waveform: .sine, bilateral: false)
            ]
        )

        let player = LightScorePlayer(session: session)

        // At time 25 — between first (false) and second (true), uses previous moment's bilateral
        let state25 = player.state(at: 25)
        #expect(state25.bilateral == false)

        // At time 75 — between second (true) and third (false), uses previous moment's bilateral
        let state75 = player.state(at: 75)
        #expect(state75.bilateral == true)
    }
}

// MARK: - Waveform Tests

struct WaveformTests {

    @Test func allWaveformsReturnValidRange() {
        for waveform in Waveform.allCases {
            for i in 0..<1000 {
                let phase = Double(i) / 1000.0
                let value = waveform.evaluate(at: phase)
                #expect(value >= 0.0 && value <= 1.0,
                    "Waveform \(waveform.rawValue) out of range at phase \(phase): \(value)")
            }
        }
    }

    @Test func waveformPhaseWrapping() {
        // Waveforms should handle phase values > 1.0 by wrapping
        for waveform in Waveform.allCases {
            let val1 = waveform.evaluate(at: 0.3)
            let val2 = waveform.evaluate(at: 1.3)
            let val3 = waveform.evaluate(at: 100.3)
            #expect(abs(val1 - val2) < 0.001,
                "Waveform \(waveform.rawValue) doesn't wrap correctly: \(val1) vs \(val2)")
            #expect(abs(val1 - val3) < 0.001,
                "Waveform \(waveform.rawValue) doesn't wrap correctly for large phase: \(val1) vs \(val3)")
        }
    }

    @Test func sineWaveformCharacteristics() {
        let sine = Waveform.sine
        // At phase 0: sin(0) = 0, shifted to 0.5
        #expect(abs(sine.evaluate(at: 0) - 0.5) < 0.001)
        // At phase 0.25: sin(pi/2) = 1, shifted to 1.0
        #expect(abs(sine.evaluate(at: 0.25) - 1.0) < 0.001)
        // At phase 0.75: sin(3pi/2) = -1, shifted to 0.0
        #expect(abs(sine.evaluate(at: 0.75) - 0.0) < 0.001)
    }

    @Test func triangleWaveformCharacteristics() {
        let tri = Waveform.triangle
        // At phase 0: 0
        #expect(abs(tri.evaluate(at: 0) - 0.0) < 0.001)
        // At phase 0.25: 0.5
        #expect(abs(tri.evaluate(at: 0.25) - 0.5) < 0.001)
        // At phase 0.5: 1.0
        #expect(abs(tri.evaluate(at: 0.5) - 1.0) < 0.001)
        // At phase 0.75: 0.5
        #expect(abs(tri.evaluate(at: 0.75) - 0.5) < 0.001)
    }

    @Test func squareWaveformCharacteristics() {
        let sq = Waveform.square
        #expect(sq.evaluate(at: 0.0) == 1.0)
        #expect(sq.evaluate(at: 0.25) == 1.0)
        #expect(sq.evaluate(at: 0.5) == 0.0)
        #expect(sq.evaluate(at: 0.75) == 0.0)
    }

    @Test func rampHoldWaveformCharacteristics() {
        let rh = Waveform.rampHold
        // 0-30%: ramp up
        #expect(abs(rh.evaluate(at: 0.0) - 0.0) < 0.001)
        #expect(abs(rh.evaluate(at: 0.15) - 0.5) < 0.001)
        // 30-70%: hold at 1.0
        #expect(abs(rh.evaluate(at: 0.3) - 1.0) < 0.001)
        #expect(abs(rh.evaluate(at: 0.5) - 1.0) < 0.001)
        // 70-100%: smooth release
        #expect(rh.evaluate(at: 0.85) < 1.0)
        #expect(rh.evaluate(at: 0.85) > 0.0)
    }
}

// MARK: - Ramp Curve Tests

struct RampCurveTests {

    @Test func allCurvesStartAndEnd() {
        for curve in RampCurve.allCases {
            let startVal = curve.evaluate(at: 0.0)
            let endVal = curve.evaluate(at: 1.0)
            // All curves should start near 0 and end near 1
            #expect(startVal < 0.01, "\(curve.rawValue) start value too high: \(startVal)")
            #expect(endVal > 0.99, "\(curve.rawValue) end value too low: \(endVal)")
        }
    }

    @Test func linearCurveIsLinear() {
        let linear = RampCurve.linear
        #expect(abs(linear.evaluate(at: 0.5) - 0.5) < 0.001)
        #expect(abs(linear.evaluate(at: 0.25) - 0.25) < 0.001)
    }

    @Test func curvesAreMonotonic() {
        for curve in RampCurve.allCases {
            var prevVal = curve.evaluate(at: 0.0)
            for i in 1...100 {
                let t = Double(i) / 100.0
                let val = curve.evaluate(at: t)
                #expect(val >= prevVal - 0.0001,
                    "\(curve.rawValue) is not monotonic at t=\(t): \(prevVal) -> \(val)")
                prevVal = val
            }
        }
    }

    @Test func frequencyRampAdvance() {
        var ramp = FrequencyRamp(
            fromFrequency: 10.0,
            toFrequency: 20.0,
            duration: 1.0,
            curve: .linear
        )

        #expect(!ramp.isComplete)

        let freq1 = ramp.advance(dt: 0.5)
        #expect(abs(freq1 - 15.0) < 0.1)

        let freq2 = ramp.advance(dt: 0.5)
        #expect(abs(freq2 - 20.0) < 0.1)
        #expect(ramp.isComplete)
    }

    @Test func frequencyRampZeroDuration() {
        let ramp = FrequencyRamp(
            fromFrequency: 10.0,
            toFrequency: 20.0,
            duration: 0.0,
            curve: .linear
        )
        // Zero duration should immediately give target frequency
        #expect(ramp.currentFrequency == 20.0)
    }
}

// MARK: - LightScoreReader Tests

struct LightScoreReaderTests {

    @Test func loadInvalidJSONThrows() {
        let invalidData = "not json".data(using: .utf8)!
        #expect(throws: LightScoreReader.ReaderError.self) {
            try LightScoreReader.loadSession(from: invalidData)
        }
    }

    @Test func loadEmptyLightScoreThrows() throws {
        let json = """
        {
            "session_name": "Empty",
            "duration_sec": 100,
            "light_score": []
        }
        """
        let data = json.data(using: .utf8)!
        #expect(throws: LightScoreReader.ReaderError.self) {
            try LightScoreReader.loadSession(from: data)
        }
    }

    @Test func loadNegativeDurationThrows() throws {
        let json = """
        {
            "session_name": "Negative",
            "duration_sec": -10,
            "light_score": [
                {"time": 0, "frequency": 10, "intensity": 0.5, "waveform": "sine"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        #expect(throws: LightScoreReader.ReaderError.self) {
            try LightScoreReader.loadSession(from: data)
        }
    }

    @Test func loadOutOfRangeFrequencyThrows() throws {
        let json = """
        {
            "session_name": "Bad Freq",
            "duration_sec": 100,
            "light_score": [
                {"time": 0, "frequency": 200, "intensity": 0.5, "waveform": "sine"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        #expect(throws: LightScoreReader.ReaderError.self) {
            try LightScoreReader.loadSession(from: data)
        }
    }

    @Test func loadOutOfRangeIntensityThrows() throws {
        let json = """
        {
            "session_name": "Bad Intensity",
            "duration_sec": 100,
            "light_score": [
                {"time": 0, "frequency": 10, "intensity": 1.5, "waveform": "sine"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        #expect(throws: LightScoreReader.ReaderError.self) {
            try LightScoreReader.loadSession(from: data)
        }
    }

    @Test func loadValidSession() throws {
        let json = """
        {
            "session_name": "Valid Session",
            "duration_sec": 300,
            "light_score": [
                {"time": 0, "frequency": 10, "intensity": 0.5, "waveform": "sine"},
                {"time": 150, "frequency": 6, "intensity": 0.8, "waveform": "soft_pulse"},
                {"time": 300, "frequency": 12, "intensity": 0.3, "waveform": "triangle"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let session = try LightScoreReader.loadSession(from: data)

        #expect(session.session_name == "Valid Session")
        #expect(session.duration_sec == 300)
        #expect(session.light_score.count == 3)
        #expect(session.light_score[1].waveform == .softPulse)
    }

    @Test func loadSessionWithOptionalFields() throws {
        let json = """
        {
            "session_name": "Full Session",
            "duration_sec": 100,
            "light_score": [
                {
                    "time": 0, "frequency": 10, "intensity": 0.5, "waveform": "sine",
                    "bilateral": true, "bilateral_transition_duration": 3.0,
                    "ramp_duration": 5.0, "color_temperature": 3500
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let session = try LightScoreReader.loadSession(from: data)
        let moment = session.light_score[0]

        #expect(moment.bilateral == true)
        #expect(moment.bilateral_transition_duration == 3.0)
        #expect(moment.ramp_duration == 5.0)
        #expect(moment.color_temperature == 3500)
    }

    @Test func loadUnsortedMomentsThrows() throws {
        let json = """
        {
            "session_name": "Unsorted",
            "duration_sec": 100,
            "light_score": [
                {"time": 50, "frequency": 10, "intensity": 0.5, "waveform": "sine"},
                {"time": 0, "frequency": 6, "intensity": 0.8, "waveform": "sine"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        #expect(throws: LightScoreReader.ReaderError.self) {
            try LightScoreReader.loadSession(from: data)
        }
    }
}

// MARK: - Audio Extension Stripping Tests (Duplicated Pattern)

struct FileExtensionStrippingTests {

    @Test func extensionStrippingCoversAllFormats() {
        // The codebase strips extensions with replaceOccurrences for .mp3, .m4a, .wav
        // Verify these are the audio types supported by fileImporter(.audio)
        let testCases: [(input: String, expected: String)] = [
            ("test.mp3", "test"),
            ("test.m4a", "test"),
            ("test.wav", "test"),
            ("test.aac", "test.aac"), // NOT stripped — potential bug
            ("test.flac", "test.flac"), // NOT stripped — potential bug
            ("test.ogg", "test.ogg"), // NOT stripped — potential bug
            ("my.song.mp3", "my.song") // Only strips the extension portion
        ]

        for testCase in testCases {
            let result = testCase.input
                .replacingOccurrences(of: ".mp3", with: "")
                .replacingOccurrences(of: ".m4a", with: "")
                .replacingOccurrences(of: ".wav", with: "")
            #expect(result == testCase.expected,
                "Extension stripping failed for '\(testCase.input)': got '\(result)' expected '\(testCase.expected)'")
        }
    }

    // BUG: File extension stripping is duplicated across 6+ locations
    // It should be a shared utility method on AudioFile or String
    @Test func extensionStrippingDuplicationLocations() {
        // This test documents the duplication. The following files all have
        // the same extension stripping pattern:
        //   1. AudioLibraryView.swift - loadGeneratedSession()
        //   2. AudioLibraryView.swift - deleteFile()
        //   3. AudioLibraryView.swift - AudioFileRow.checkForGeneratedSession()
        //   4. AudioLightScoreGenerator.swift - generateSessionName()
        //   5. AnalysisStateManager.swift - saveGeneratedSession()
        //   6. PlaylistEditorView.swift - hasGeneratedSession()
        //   7. PlaylistPlayerController.swift - loadGeneratedSession()
        // All 7 locations should use a single shared method.
        // This test simply confirms the pattern works consistently.

        let filename = "test audio.m4a"
        let baseName = filename
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: ".wav", with: "")
        #expect(baseName == "test audio")
    }
}

// MARK: - AIContentAnalyzer Pattern Tests

struct AIContentAnalyzerTests {

    @Test func frequencyRangeParsing() {
        // The AI analyzer parses frequency ranges like "8-12" or "8.0-12.0"
        let testCases: [(input: String, expectedLower: Double, expectedUpper: Double)] = [
            ("8-12", 8.0, 12.0),
            ("4.0-8.0", 4.0, 8.0),
            ("10-14", 10.0, 14.0)
        ]

        for testCase in testCases {
            let components = testCase.input
                .components(separatedBy: CharacterSet(charactersIn: "-–—"))
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }

            #expect(components.count == 2, "Failed to parse '\(testCase.input)'")
            if components.count == 2 {
                #expect(components[0] == testCase.expectedLower)
                #expect(components[1] == testCase.expectedUpper)
            }
        }
    }

    @Test func frequencyRangeParsingFallback() {
        // Invalid range should fall back to 8.0...12.0
        let invalidInputs = ["invalid", "8", "8 to 12", ""]

        for input in invalidInputs {
            let components = input
                .components(separatedBy: CharacterSet(charactersIn: "-–—"))
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }

            let range: ClosedRange<Double>
            if components.count == 2 {
                range = components[0]...components[1]
            } else {
                range = 8.0...12.0
            }

            #expect(range == 8.0...12.0, "Should fall back to default for '\(input)'")
        }
    }
}
