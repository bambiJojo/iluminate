//
//  TechniqueDetectorTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

private func makeWordTimestamps(_ text: String) -> [WordTimestamp] {
    text
        .split(separator: " ")
        .enumerated()
        .map { index, token in
            WordTimestamp(word: String(token), startTime: Double(index), duration: 0.8)
        }
}

struct TechniqueDetectorTests {

    @Test func detectsSuggestibilityTestingFromManualStylePretalk() {
        let detector = TechniqueDetector()
        let words = makeWordTimestamps("this suggestibility test explains the critical mind and what is hypnosis")

        let result = detector.detect(
            wordTimestamps: words,
            segments: [],
            prosodic: nil,
            duration: 60
        )

        #expect(result.markers.contains(where: { $0.type == .suggestibilityTesting }))
    }

    @Test func detectsTriggerInstallationFromManualStyleConditioning() {
        let detector = TechniqueDetector()
        let words = makeWordTimestamps("next time you hear the word sleep when i say drift you drop deeper")

        let result = detector.detect(
            wordTimestamps: words,
            segments: [],
            prosodic: nil,
            duration: 120
        )

        #expect(result.markers.contains(where: { $0.type == .triggerInstallation }))
    }

    @Test func detectsMetaphoricalStoryAndUtilizationFromEricksonianLanguage() {
        let detector = TechniqueDetector()
        let words = makeWordTimestamps("let me tell you a story and that's right you can notice your unconscious mind responding in your own way")

        let result = detector.detect(
            wordTimestamps: words,
            segments: [],
            prosodic: nil,
            duration: 180
        )

        #expect(result.markers.contains(where: { $0.type == .metaphoricalStory }))
        #expect(result.markers.contains(where: { $0.type == .utilizationOfResponse }))
    }
}
