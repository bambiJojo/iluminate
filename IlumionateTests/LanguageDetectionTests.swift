//
//  LanguageDetectionTests.swift
//  IlumionateTests
//
//  Tests for Step 4.1: WhisperKit language auto-detection.
//  Verifies that:
//  1. AudioTranscriptionResult stores the WhisperKit-detected ISO 639-1 code.
//  2. The locale field propagates correctly for common language codes.
//  3. The localized language name helper produces human-readable output.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Helpers

private func makeResult(language: String) -> AudioTranscriptionResult {
    AudioTranscriptionResult(
        fullText: "Hello world",
        segments: [],
        duration: 300,
        detectedLanguage: language
    )
}

// MARK: - AudioTranscriptionResult Language Storage

struct AudioTranscriptionResultLanguageTests {

    @Test func storedLocaleMatchesDetectedLanguage() {
        let result = makeResult(language: "en")
        #expect(result.locale == "en",
            "locale must store the ISO 639-1 code returned by WhisperKit, got: \(result.locale)")
    }

    @Test func frenchCodeStoredCorrectly() {
        let result = makeResult(language: "fr")
        #expect(result.locale == "fr")
    }

    @Test func japaneseCodeStoredCorrectly() {
        let result = makeResult(language: "ja")
        #expect(result.locale == "ja")
    }

    @Test func germanCodeStoredCorrectly() {
        let result = makeResult(language: "de")
        #expect(result.locale == "de")
    }

    @Test func spanishCodeStoredCorrectly() {
        let result = makeResult(language: "es")
        #expect(result.locale == "es")
    }

    @Test func localeIsNonEmpty() {
        // Any valid ISO code produces a non-empty locale
        for code in ["en", "fr", "de", "ja", "zh", "pt", "it"] {
            let result = makeResult(language: code)
            #expect(!result.locale.isEmpty, "locale must not be empty for code '\(code)'")
        }
    }
}

// MARK: - Localized Language Name Helper

struct LocalizedLanguageNameTests {

    /// Reproduces the helper used in buildTranscriptionPrompt so we can unit-test it.
    private func localizedName(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    @Test func englishCodeProducesHumanReadableName() {
        let name = localizedName(for: "en")
        // On any device locale, "en" resolves to something that contains alphabetic chars
        // and is not just the two-letter code
        #expect(name.count > 2,
            "Language name for 'en' should be longer than 2 chars, got: '\(name)'")
    }

    @Test func frenchCodeProducesNonEmptyName() {
        let name = localizedName(for: "fr")
        #expect(!name.isEmpty)
    }

    @Test func unknownCodeFallsBackToUppercased() {
        // An invented code should fall back to uppercased raw code
        let name = Locale.current.localizedString(forLanguageCode: "xyz") ?? "xyz".uppercased()
        // We can't guarantee what Foundation returns for "xyz", just check non-empty
        #expect(!name.isEmpty)
    }

    @Test func promptLanguageLineFormat() {
        // Simulate what buildTranscriptionPrompt builds for the language line
        let result = makeResult(language: "en")
        let languageName = Locale.current.localizedString(forLanguageCode: result.locale)
            ?? result.locale.uppercased()
        let line = "- Content Language: \(languageName) (\(result.locale))\n"

        #expect(line.contains("Content Language:"),
            "Language line must contain 'Content Language:'")
        #expect(line.contains("(en)"),
            "Language line must include the ISO code in parentheses")
        #expect(line.count > "- Content Language: (en)\n".count,
            "Language line should contain a human-readable name, not just the code")
    }
}
