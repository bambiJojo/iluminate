//
//  PlaylistBrowserHomePage.swift
//  Ilumionate
//
//  Where "Browse for Playlists" opens. The user picks the site in Settings;
//  the app ships no site of its own beyond a general search engine.
//

import Foundation

nonisolated enum PlaylistBrowserHomePage {

    /// `@AppStorage` key for the address typed in Settings.
    static let storageKey = "playlistBrowserHomePage"

    /// Used when nothing is set, or when the setting cannot be opened.
    // A literal address: this cannot fail to parse.
    static let fallbackURL = URL(string: "https://www.google.com")!

    /// The page the browser should load for a stored setting.
    ///
    /// Accepts the same addresses as pasted playlist links — a bare host gets
    /// `https`, and anything that is not an `http`/`https` address with a real
    /// host is ignored rather than handed to the web view.
    static func startURL(for setting: String) -> URL {
        (try? PlaylistSourceURL.normalized(setting)) ?? fallbackURL
    }

    /// What "Set as Start Page" stores for the page being viewed, or `nil` when
    /// the page could not be reopened from Settings (`about:`, `file:`, `data:`).
    /// Held to the same rule as a typed address, so saving never produces a
    /// setting that Settings would then flag as unusable.
    static func settingValue(for url: URL) -> String? {
        (try? PlaylistSourceURL.normalized(url.absoluteString))?.absoluteString
    }

    /// Whether `url` is the page the browser would open on. Sites routinely
    /// redirect a bare address to add a trailing slash, and hosts are
    /// case-insensitive, so neither difference counts.
    static func isStartPage(_ url: URL?, setting: String) -> Bool {
        guard let url, let key = comparisonKey(for: url) else { return false }
        return key == comparisonKey(for: startURL(for: setting))
    }

    private static func comparisonKey(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased()
        else { return nil }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        let port = components.port.map { ":\($0)" } ?? ""
        let query = components.query.map { "?\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)\(path)\(query)"
    }

    /// Whether Settings should accept the typed address. Empty is fine — it
    /// means "use the default".
    static func isUsable(_ setting: String) -> Bool {
        setting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (try? PlaylistSourceURL.normalized(setting)) != nil
    }
}
