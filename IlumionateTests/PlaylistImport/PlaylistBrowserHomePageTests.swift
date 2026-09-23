import Foundation
import Testing
@testable import Ilumionate

@Suite("Playlist browser start page")
struct PlaylistBrowserHomePageTests {

    @Test("With nothing set, the browser starts at Google")
    func emptySettingFallsBackToGoogle() {
        #expect(PlaylistBrowserHomePage.startURL(for: "").absoluteString == "https://www.google.com")
        #expect(PlaylistBrowserHomePage.startURL(for: "   \n").absoluteString == "https://www.google.com")
    }

    @Test("A bare host is opened over https")
    func bareHostGetsHTTPS() {
        let url = PlaylistBrowserHomePage.startURL(for: "  example.com/playlists ")

        #expect(url.absoluteString == "https://example.com/playlists")
    }

    @Test("A full address is kept as entered")
    func fullAddressIsKept() {
        let url = PlaylistBrowserHomePage.startURL(for: "http://music.example.org/browse?page=2")

        #expect(url.absoluteString == "http://music.example.org/browse?page=2")
    }

    @Test(
        "An unusable setting falls back to Google instead of opening a blank page",
        arguments: ["javascript:alert(1)", "file:///etc/hosts", "not a site", "localhost"]
    )
    func unusableSettingFallsBack(_ setting: String) {
        #expect(PlaylistBrowserHomePage.startURL(for: setting).absoluteString == "https://www.google.com")
    }

    @Test("Settings flags only a non-empty address it cannot open")
    func validity() {
        #expect(PlaylistBrowserHomePage.isUsable(""))
        #expect(PlaylistBrowserHomePage.isUsable("example.com"))
        #expect(PlaylistBrowserHomePage.isUsable("https://example.com/x"))
        #expect(PlaylistBrowserHomePage.isUsable("javascript:alert(1)") == false)
        #expect(PlaylistBrowserHomePage.isUsable("not a site") == false)
    }
}
