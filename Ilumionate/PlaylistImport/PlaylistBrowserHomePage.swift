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

    /// Whether Settings should accept the typed address. Empty is fine — it
    /// means "use the default".
    static func isUsable(_ setting: String) -> Bool {
        setting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (try? PlaylistSourceURL.normalized(setting)) != nil
    }
}
