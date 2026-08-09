//
//  AudioLinkDiscoveryTests.swift
//  IlumionateTests
//
//  The in-app browser only ever noticed audio the user tapped. Discovery scans
//  the page instead. The scan runs against untrusted markup, so the parsing rules
//  — what counts as audio, what is unreachable, what is a duplicate — are pinned
//  here rather than left to the injected script.
//

import Foundation
import Testing

@testable import Ilumionate

@Suite("Audio link discovery")
struct AudioLinkDiscoveryTests {

    private let page = URL(string: "https://example.com/tracks/index.html")!

    // MARK: - Finding links

    @Test("Keeps direct audio links")
    func keepsAudioLinks() {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [
                ["href": "https://example.com/a.mp3", "title": "Session One"]
            ],
            pageURL: page
        )

        #expect(links.count == 1)
        #expect(links.first?.url.absoluteString == "https://example.com/a.mp3")
        #expect(links.first?.title == "Session One")
    }

    @Test("Resolves relative and root-relative paths against the page")
    func resolvesRelativePaths() {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [
                ["href": "deep.m4a", "title": ""],
                ["href": "/audio/root.wav", "title": ""],
                ["href": "../up.flac", "title": ""]
            ],
            pageURL: page
        )

        #expect(links.map(\.url.absoluteString) == [
            "https://example.com/tracks/deep.m4a",
            "https://example.com/audio/root.wav",
            "https://example.com/up.flac"
        ])
    }

    @Test("Accepts every supported extension", arguments: [
        "mp3", "m4a", "wav", "aac", "flac", "ogg"
    ])
    func acceptsSupportedExtensions(ext: String) {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [["href": "https://example.com/track.\(ext)", "title": ""]],
            pageURL: page
        )

        #expect(links.count == 1)
    }

    @Test("Ignores a query string when reading the extension")
    func ignoresQueryString() {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [
                ["href": "https://cdn.example.com/t.mp3?token=abc&x=1", "title": ""]
            ],
            pageURL: page
        )

        #expect(links.count == 1)
    }

    // MARK: - Rejecting what cannot be downloaded

    @Test("Drops schemes the downloader cannot fetch", arguments: [
        "blob:https://example.com/9f8c-2b1a",
        "data:audio/mpeg;base64,SUQzBA",
        "javascript:play()",
        "file:///etc/passwd"
    ])
    func dropsUnfetchableSchemes(href: String) {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [["href": href, "title": ""]],
            pageURL: page
        )

        #expect(links.isEmpty)
    }

    @Test("Drops streaming manifests, which are not a single file")
    func dropsStreamingManifests() {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [
                ["href": "https://example.com/stream.m3u8", "title": ""],
                ["href": "https://example.com/dash.mpd", "title": ""]
            ],
            pageURL: page
        )

        #expect(links.isEmpty)
    }

    @Test("Drops non-audio links")
    func dropsNonAudio() {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [
                ["href": "https://example.com/page.html", "title": "Home"],
                ["href": "https://example.com/image.png", "title": "Art"],
                ["href": "", "title": "Empty"]
            ],
            pageURL: page
        )

        #expect(links.isEmpty)
    }

    // MARK: - Presentation

    @Test("Collapses duplicates, keeping the first title")
    func collapsesDuplicates() {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [
                ["href": "https://example.com/a.mp3", "title": "Download"],
                ["href": "https://example.com/a.mp3", "title": "Listen"],
                ["href": "a.mp3", "title": ""]
            ],
            pageURL: URL(string: "https://example.com/index.html")!
        )

        #expect(links.count == 1)
        #expect(links.first?.title == "Download")
    }

    @Test("Falls back to the filename when the page gives no label")
    func fallsBackToFilename() {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [
                ["href": "https://example.com/deep-relaxation.mp3", "title": "   "]
            ],
            pageURL: page
        )

        #expect(links.first?.title == "deep-relaxation.mp3")
    }

    @Test("Preserves page order")
    func preservesOrder() {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [
                ["href": "https://example.com/c.mp3", "title": ""],
                ["href": "https://example.com/a.mp3", "title": ""],
                ["href": "https://example.com/b.mp3", "title": ""]
            ],
            pageURL: page
        )

        #expect(links.map(\.url.lastPathComponent) == ["c.mp3", "a.mp3", "b.mp3"])
    }

    @Test("Survives malformed entries without crashing")
    func survivesMalformedEntries() {
        let links = AudioLinkDiscovery.links(
            fromRawEntries: [
                [:],
                ["title": "no href"],
                ["href": "   "],
                ["href": "https://example.com/ok.mp3", "title": "Fine"]
            ],
            pageURL: nil
        )

        #expect(links.count == 1)
        #expect(links.first?.title == "Fine")
    }
}
