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

    // MARK: - Set as Start Page

    @Test("The page being viewed is saved as its full address")
    func webPageBecomesSetting() throws {
        let url = try #require(URL(string: "https://example.com/playlists?sort=new"))

        #expect(PlaylistBrowserHomePage.settingValue(for: url) == "https://example.com/playlists?sort=new")
    }

    @Test(
        "Pages that could not be reopened are not offered as a start page",
        arguments: ["about:blank", "file:///etc/hosts", "data:text/html,hi"]
    )
    func nonWebPageIsNotSaved(_ address: String) throws {
        let url = try #require(URL(string: address))

        #expect(PlaylistBrowserHomePage.settingValue(for: url) == nil)
    }

    /// Google redirects the bare fallback to `https://www.google.com/`; that is
    /// still the start page, so the button must show it as already set.
    @Test("The default start page is recognised after its trailing-slash redirect")
    func defaultStartPageIsRecognised() throws {
        let landed = try #require(URL(string: "https://www.google.com/"))

        #expect(PlaylistBrowserHomePage.isStartPage(landed, setting: ""))
    }

    @Test("A saved start page is recognised regardless of host case or trailing slash")
    func savedStartPageIsRecognised() throws {
        let landed = try #require(URL(string: "https://Example.com/playlists/"))

        #expect(PlaylistBrowserHomePage.isStartPage(landed, setting: "example.com/playlists"))
    }

    @Test("Another page on the same site is not the start page")
    func otherPageIsNotStartPage() throws {
        let elsewhere = try #require(URL(string: "https://example.com/playlist/42"))

        #expect(PlaylistBrowserHomePage.isStartPage(elsewhere, setting: "example.com/playlists") == false)
        #expect(PlaylistBrowserHomePage.isStartPage(nil, setting: "") == false)
    }

    @Test("Fragment routes identify different start pages")
    func fragmentRoutesRemainDistinct() throws {
        let setting = "https://example.com/#/playlist/first"
        let second = try #require(URL(string: "https://example.com/#/playlist/second"))
        let saved = try #require(URL(string: setting))
        let noFragment = try #require(URL(string: "https://example.com/"))

        #expect(!PlaylistBrowserHomePage.isStartPage(second, setting: setting))
        #expect(!PlaylistBrowserHomePage.isStartPage(noFragment, setting: setting))
        #expect(PlaylistBrowserHomePage.isStartPage(saved, setting: setting))
        let newSetting = try #require(PlaylistBrowserHomePage.settingValue(for: second))
        #expect(newSetting == second.absoluteString)
        #expect(PlaylistBrowserHomePage.startURL(for: newSetting) == second)
        #expect(PlaylistBrowserHomePage.isStartPage(second, setting: newSetting))
        #expect(!PlaylistBrowserHomePage.isStartPage(saved, setting: newSetting))
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
