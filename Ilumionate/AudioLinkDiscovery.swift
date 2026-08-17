//
//  AudioLinkDiscovery.swift
//  Ilumionate
//
//  Finds downloadable audio referenced by a web page.
//
//  The in-app browser could already intercept audio the user navigated to, but a
//  track sitting in an `<audio>` element or behind a play button was invisible
//  unless they happened to tap the right thing. This scans the page and offers
//  what it finds.
//
//  ONLY PLAIN FILES. `blob:` and `data:` URLs belong to the page's own runtime,
//  and HLS/DASH manifests describe a stream assembled from many segments — none
//  of them is a file the downloader can fetch. They are dropped during parsing
//  rather than offered and then failing, which is the more annoying outcome.
//

import Foundation

struct DiscoveredAudioLink: Identifiable, Equatable, Sendable {
    let url: URL
    let title: String

    var id: URL { url }
}

enum AudioLinkDiscovery {

    /// Extensions worth offering. Broader than the import validator's set because
    /// `ogg` is common on the web; the download path still validates the bytes.
    static let linkExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg"]

    /// Manifests that describe a stream rather than a file.
    private static let streamingExtensions: Set<String> = ["m3u8", "mpd", "ts"]

    private static let fetchableSchemes: Set<String> = ["http", "https"]

    // MARK: - Parsing

    /// Normalizes the raw `{href, title}` pairs collected from the page.
    ///
    /// Runs on untrusted markup, so every field is treated as optional and
    /// anything unusable is dropped rather than repaired.
    static func links(
        fromRawEntries entries: [[String: String]],
        pageURL: URL?
    ) -> [DiscoveredAudioLink] {
        var seen = Set<URL>()
        var results: [DiscoveredAudioLink] = []

        for entry in entries {
            let href = (entry["href"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { continue }
            guard let url = resolve(href: href, against: pageURL) else { continue }
            guard isDownloadableAudio(url) else { continue }
            guard seen.insert(url).inserted else { continue }

            let rawTitle = (entry["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rawTitle.isEmpty ? url.lastPathComponent : rawTitle
            results.append(DiscoveredAudioLink(url: url, title: title))
        }

        return results
    }

    private static func resolve(href: String, against pageURL: URL?) -> URL? {
        if let absolute = URL(string: href), absolute.scheme != nil {
            return absolute
        }
        guard let pageURL else { return nil }
        return URL(string: href, relativeTo: pageURL)?.absoluteURL
    }

    private static func isDownloadableAudio(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              fetchableSchemes.contains(scheme) else { return false }

        // Strip any query before reading the extension — CDN links routinely
        // carry signing tokens after the filename.
        let ext = url.pathExtension.lowercased()
        guard !streamingExtensions.contains(ext) else { return false }
        return linkExtensions.contains(ext)
    }

    // MARK: - Collection

    /// Collects candidate audio references from the live DOM.
    ///
    /// Returns `[{href, title}]`. Absolute URLs come from the DOM's own
    /// resolution where possible (`.src`/`.href` properties are already
    /// absolute), and parsing re-resolves anything that isn't.
    static let collectionScript = """
    (function () {
        var out = [];
        function add(href, title) {
            if (!href) { return; }
            out.push({ href: String(href), title: String(title || '') });
        }
        document.querySelectorAll('audio[src]').forEach(function (el) {
            add(el.src, el.getAttribute('title') || el.getAttribute('aria-label'));
        });
        document.querySelectorAll('audio source[src], video source[src]').forEach(function (el) {
            add(el.src, el.getAttribute('title'));
        });
        document.querySelectorAll('a[href]').forEach(function (el) {
            add(el.href, (el.textContent || '').trim().slice(0, 120));
        });
        document.querySelectorAll('[data-audio-url], [data-src], [data-track-url]').forEach(function (el) {
            add(
                el.getAttribute('data-audio-url') || el.getAttribute('data-src') || el.getAttribute('data-track-url'),
                (el.getAttribute('title') || el.textContent || '').trim().slice(0, 120)
            );
        });
        return out;
    })();
    """
}
