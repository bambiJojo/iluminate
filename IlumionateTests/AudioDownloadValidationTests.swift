//
//  AudioDownloadValidationTests.swift
//  IlumionateTests
//
//  A URL that returns a web page used to be saved as `.mp3` and admitted to the
//  library, where it looked like a normal track, failed transcription twice, and
//  was parked silently. Reproduced 2026-08-09: 30KB of HTML stored as
//  `1062-stolen_thoughts.mp3`. These tests pin the gate that stops it.
//

import Foundation
import Testing

@testable import Ilumionate

@Suite("Audio download validation")
struct AudioDownloadValidationTests {

    // MARK: - The regression

    @Test("An HTML page is rejected even when the URL claims .mp3")
    func htmlPageIsRejected() {
        let html = Data("<!DOCTYPE html>\n<html lang=\"en\">\n<head>".utf8)

        let rejection = AudioDownloadValidation.rejectionReason(
            contentType: "text/html; charset=utf-8",
            data: html
        )

        #expect(rejection == .unsupportedContentType("text/html; charset=utf-8"))
    }

    @Test("HTML with a lying audio Content-Type is still rejected on its bytes")
    func htmlWithSpoofedContentTypeIsRejected() {
        // Some servers return an error page with the originally requested type.
        let html = Data("<!DOCTYPE html><html><body>404</body></html>".utf8)

        let rejection = AudioDownloadValidation.rejectionReason(
            contentType: "audio/mpeg",
            data: html
        )

        #expect(rejection == .notAudioData)
    }

    @Test("Rejects other non-audio payloads", arguments: [
        "<?xml version=\"1.0\"?><rss></rss>",
        "{\"error\":\"not found\"}",
        "<html><head><title>Sign in</title></head></html>"
    ])
    func rejectsNonAudioPayloads(body: String) {
        let rejection = AudioDownloadValidation.rejectionReason(
            contentType: nil,
            data: Data(body.utf8)
        )

        #expect(rejection != nil)
    }

    @Test("An empty response is rejected")
    func emptyResponseIsRejected() {
        #expect(
            AudioDownloadValidation.rejectionReason(contentType: nil, data: Data())
            == .notAudioData
        )
    }

    // MARK: - Real audio still passes

    @Test("Accepts the supported container signatures")
    func acceptsSupportedContainers() {
        for (name, header) in Self.audioSignatures {
            let rejection = AudioDownloadValidation.rejectionReason(
                contentType: nil,
                data: header
            )

            #expect(rejection == nil, "\(name) should be accepted")
        }
    }

    @Test("Accepts audio bytes even when the server sends no Content-Type")
    func acceptsAudioWithoutContentType() {
        let mp3 = Self.signature([0x49, 0x44, 0x33, 0x04, 0x00, 0x00])

        #expect(
            AudioDownloadValidation.rejectionReason(contentType: nil, data: mp3) == nil
        )
    }

    @Test("Accepts an octet-stream that really is audio")
    func acceptsOctetStreamAudio() {
        let m4a = Self.signature(
            [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20]
        )

        #expect(
            AudioDownloadValidation.rejectionReason(
                contentType: "application/octet-stream",
                data: m4a
            ) == nil
        )
    }

    // MARK: - Extension mapping

    @Test("Maps audio content types to extensions", arguments: [
        ("audio/mpeg", "mp3"),
        ("audio/mp3", "mp3"),
        ("audio/mp4", "m4a"),
        ("audio/x-m4a", "m4a"),
        ("audio/wav", "wav"),
        ("audio/x-wav", "wav"),
        ("audio/aac", "aac"),
        ("audio/flac", "flac")
    ])
    func mapsContentTypesToExtensions(pair: (contentType: String, expected: String)) {
        #expect(
            AudioDownloadValidation.audioExtension(forContentType: pair.contentType)
            == pair.expected
        )
    }

    @Test("Refuses to guess an extension for non-audio types", arguments: [
        "text/html", "application/json", "text/plain", "image/png"
    ])
    func refusesToGuessForNonAudio(contentType: String) {
        #expect(
            AudioDownloadValidation.audioExtension(forContentType: contentType) == nil
        )
    }

    @Test("Infers an extension from the bytes when the header is unhelpful")
    func infersExtensionFromBytes() {
        let wav = Self.signature(
            [0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45]
        )

        #expect(AudioDownloadValidation.inferredExtension(from: wav) == "wav")
        #expect(AudioDownloadValidation.inferredExtension(from: Data("<html>".utf8)) == nil)
    }

    // MARK: - Fixtures

    /// Leading bytes padded out so length checks cannot pass by accident.
    private static func signature(_ bytes: [UInt8]) -> Data {
        Data(bytes) + Data(repeating: 0, count: 64)
    }

    private static let audioSignatures: [(String, Data)] = [
        ("MP3 with ID3 tag", signature([0x49, 0x44, 0x33, 0x04])),
        ("MP3 frame sync", signature([0xFF, 0xFB, 0x90, 0x00])),
        ("M4A ftyp", signature([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70,
                                0x4D, 0x34, 0x41, 0x20])),
        ("WAV RIFF", signature([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00,
                                0x57, 0x41, 0x56, 0x45])),
        ("FLAC", signature([0x66, 0x4C, 0x61, 0x43, 0x00])),
        ("AAC ADTS", signature([0xFF, 0xF1, 0x50, 0x80]))
    ]
}
