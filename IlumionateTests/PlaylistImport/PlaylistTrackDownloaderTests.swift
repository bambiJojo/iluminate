//
//  PlaylistTrackDownloaderTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct PlaylistTrackDownloaderTests {
    private func makeTrack(
        name: String = "Rapid Induction",
        audioURL: String?,
        duration: Double = 162_000
    ) throws -> SourcePlaylistTrack {
        let audioField = audioURL.map { "\"audioURL\": \"\($0)\"," } ?? ""
        let json = """
        {"playlists":[{"uuid":"\(UUID().uuidString)","name":"P","files":[
        {"uuid":"\(UUID().uuidString)","name":"\(name)","duration":\(duration),
         \(audioField)"trackNum":0}]}]}
        """
        let data = Data(json.utf8)
        let envelopeID = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let playlists = try #require(envelopeID["playlists"] as? [[String: Any]])
        let uuid = try #require(UUID(uuidString: playlists[0]["uuid"] as! String))
        let playlist = try GenericPlaylistJSON.playlist(from: data)
        return try #require(playlist.tracks.first)
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func trackWithoutAudioURLReportsNoSource() async throws {
        let track = try makeTrack(audioURL: nil)
        let downloader = PlaylistTrackDownloader(
            documentsURL: try temporaryDirectory(),
            playlistSource: URL(string: "https://example.com/list.json")
        ) { _ in
            Issue.record("Download attempted with no source")
            throw PlaylistTrackDownloadError.networkUnavailable
        }

        await #expect(throws: PlaylistTrackDownloadError.noSourceAvailable) {
            try await downloader.download(track)
        }
    }

    @Test("With no known playlist source, nothing is downloadable")
    func unknownPlaylistSourceRefusesEverything() async throws {
        let track = try makeTrack(audioURL: "https://cdn.example.com/a.mp3")
        let downloader = PlaylistTrackDownloader(
            documentsURL: try temporaryDirectory(),
            playlistSource: nil
        ) { _ in
            Issue.record("Download attempted with no playlist source")
            throw PlaylistTrackDownloadError.networkUnavailable
        }

        await #expect(throws: PlaylistTrackDownloadError.unsupportedSource) {
            try await downloader.download(track)
        }
    }

    @Test func offDomainSourceIsRefusedWithoutRequesting() async throws {
        let track = try makeTrack(audioURL: "https://cdn.evil.example/track.mp3")
        let downloader = PlaylistTrackDownloader(
            documentsURL: try temporaryDirectory(),
            playlistSource: URL(string: "https://example.com/list.json")
        ) { _ in
            Issue.record("Download attempted for an off-domain source")
            throw PlaylistTrackDownloadError.networkUnavailable
        }

        await #expect(throws: PlaylistTrackDownloadError.unsupportedSource) {
            try await downloader.download(track)
        }
    }

    @Test func lookalikeHostIsRefused() async throws {
        let track = try makeTrack(
            audioURL: "https://example.com.attacker.example/track.mp3"
        )
        let downloader = PlaylistTrackDownloader(
            documentsURL: try temporaryDirectory(),
            playlistSource: URL(string: "https://example.com/list.json")
        ) { _ in
            Issue.record("Download attempted for a lookalike host")
            throw PlaylistTrackDownloadError.networkUnavailable
        }

        await #expect(throws: PlaylistTrackDownloadError.unsupportedSource) {
            try await downloader.download(track)
        }
    }

    @Test func plainHTTPSourceIsRefused() async throws {
        let track = try makeTrack(audioURL: "http://cdn.example.com/track.mp3")
        let downloader = PlaylistTrackDownloader(
            documentsURL: try temporaryDirectory(),
            playlistSource: URL(string: "https://example.com/list.json")
        ) { _ in
            Issue.record("Download attempted over plain http")
            throw PlaylistTrackDownloadError.networkUnavailable
        }

        await #expect(throws: PlaylistTrackDownloadError.unsupportedSource) {
            try await downloader.download(track)
        }
    }

    /// The saved file is named after the track so the importer's title matching
    /// finds it on a later import.
    @Test func downloadedFileIsNamedAfterTheTrack() async throws {
        let documents = try temporaryDirectory()
        let track = try makeTrack(
            name: "Bubble Induction",
            audioURL: "https://cdn.example.com/abc.mp3"
        )
        let payload = Data(repeating: 0, count: 2_048)

        let downloader = PlaylistTrackDownloader(
            documentsURL: documents,
            playlistSource: URL(string: "https://example.com/list.json")
        ) { url in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try payload.write(to: temp)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (temp, response)
        }

        guard case .saved(let audioFile) = try await downloader.download(track) else {
            Issue.record("Expected the track to be saved")
            return
        }

        #expect(audioFile.filename == "Bubble Induction.mp3")
        #expect(audioFile.fileSize == 2_048)
        #expect(
            FileManager.default.fileExists(
                atPath: documents.appending(path: "Bubble Induction.mp3").path
            )
        )
    }

    @Test func repeatDownloadDoesNotOverwriteAnExistingFile() async throws {
        let documents = try temporaryDirectory()
        let existing = documents.appending(path: "Bubble Induction.mp3")
        try Data(repeating: 9, count: 16).write(to: existing)

        let track = try makeTrack(
            name: "Bubble Induction",
            audioURL: "https://cdn.example.com/abc.mp3"
        )
        let downloader = PlaylistTrackDownloader(
            documentsURL: documents,
            playlistSource: URL(string: "https://example.com/list.json")
        ) { url in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try Data(repeating: 1, count: 32).write(to: temp)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (temp, response)
        }

        // Genuinely different content, and no library index — a real filename
        // collision still resolves by suffixing. Only a *duplicate* is now
        // recognised before anything is written.
        guard case .saved(let audioFile) = try await downloader.download(track) else {
            Issue.record("Expected the track to be saved")
            return
        }

        #expect(audioFile.filename == "Bubble Induction (1).mp3")
        // The original file is untouched.
        #expect(try Data(contentsOf: existing).count == 16)
    }

    /// A large file is no longer refused outright — it asks, reporting the size.
    @Test func oversizedTrackAsksForConfirmationInsteadOfFailing() async throws {
        let documents = try temporaryDirectory()
        let track = try makeTrack(audioURL: "https://cdn.example.com/abc.mp3")
        let hugeByteCount: Int64 = 400_000_000

        let downloader = PlaylistTrackDownloader(
            documentsURL: documents,
            playlistSource: URL(string: "https://example.com/list.json")
        ) { url in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try Data(repeating: 0, count: 64).write(to: temp)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(hugeByteCount)"]
            )!
            return (temp, response)
        }

        await #expect(
            throws: PlaylistTrackDownloadError.confirmationRequired(
                byteCount: hugeByteCount
            )
        ) {
            try await downloader.download(track)
        }
    }

    /// Once confirmed there is no ceiling: the same file downloads.
    @Test func confirmedOversizedTrackDownloads() async throws {
        let documents = try temporaryDirectory()
        let track = try makeTrack(
            name: "Bambi Therapy Pretty in Pink",
            audioURL: "https://cdn.example.com/abc.mp3"
        )

        let downloader = PlaylistTrackDownloader(
            documentsURL: documents,
            playlistSource: URL(string: "https://example.com/list.json")
        ) { url in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try Data(repeating: 0, count: 64).write(to: temp)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "400000000"]
            )!
            return (temp, response)
        }

        guard case .saved(let audioFile) = try await downloader.download(
            track,
            allowingLargeFile: true
        ) else {
            Issue.record("Expected the track to be saved")
            return
        }

        #expect(audioFile.filename == "Bambi Therapy Pretty in Pink.mp3")
    }

    @Test func expectedSizeReadsContentLengthWithoutFetching() async throws {
        let track = try makeTrack(audioURL: "https://cdn.example.com/abc.mp3")
        let downloader = PlaylistTrackDownloader(
            documentsURL: try temporaryDirectory(),
            playlistSource: URL(string: "https://example.com/list.json"),
            probe: { request in
                #expect(request.httpMethod == "HEAD")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": "412000000"]
                )!
                return (Data(), response)
            }
        ) { _ in
            Issue.record("Probing must not download the file")
            throw PlaylistTrackDownloadError.networkUnavailable
        }

        let size = try await downloader.expectedSize(of: track)

        #expect(size == 412_000_000)
    }

    @Test func serverErrorSurfacesAsNetworkFailure() async throws {
        let track = try makeTrack(audioURL: "https://cdn.example.com/abc.mp3")
        let downloader = PlaylistTrackDownloader(
            documentsURL: try temporaryDirectory(),
            playlistSource: URL(string: "https://example.com/list.json")
        ) { url in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try Data().write(to: temp)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (temp, response)
        }

        await #expect(throws: PlaylistTrackDownloadError.networkUnavailable) {
            try await downloader.download(track)
        }
    }

    @Test("A saved download carries its fingerprint and its provenance")
    func savedDownloadCarriesIdentity() async throws {
        let track = try makeTrack(audioURL: "https://cdn.example.com/a.mp3")
        let documents = try temporaryDirectory()

        let downloader = PlaylistTrackDownloader(
            documentsURL: documents,
            playlistSource: URL(string: "https://example.com/list.json")
        ) { _ in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try Data("audio-bytes".utf8).write(to: temp)
            return (temp, URLResponse())
        }

        guard case .saved(let audioFile) = try await downloader.download(track) else {
            Issue.record("Expected the track to be saved")
            return
        }

        #expect(audioFile.contentFingerprint?.count == 64)
        #expect(audioFile.remoteSource?.service == "cdn.example.com")
        #expect(audioFile.remoteSource?.trackID == track.id)
        #expect(audioFile.remoteSource?.url.absoluteString == "https://cdn.example.com/a.mp3")
    }

    // The whole point of the feature: identical bytes must not become a second
    // file on disk. The old code called `uniqueDestination` first and so had
    // already created "Rapid Induction (1).mp3" before anything could object.
    @Test("Downloading content the library already holds writes nothing")
    func identicalContentIsNotSavedTwice() async throws {
        let track = try makeTrack(audioURL: "https://cdn.example.com/a.mp3")
        let documents = try temporaryDirectory()
        let payload = Data("audio-bytes".utf8)

        let downloader = PlaylistTrackDownloader(
            documentsURL: documents,
            playlistSource: URL(string: "https://example.com/list.json")
        ) { _ in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try payload.write(to: temp)
            return (temp, URLResponse())
        }

        guard case .saved(let savedFile) = try await downloader.download(track) else {
            Issue.record("First download should save")
            return
        }

        let second = try await downloader.download(
            track,
            existing: DuplicateAudioIndex([savedFile])
        )

        #expect(second == .alreadyInLibrary(existing: savedFile.id))

        let contents = try FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: nil
        )
        #expect(contents.count == 1)
        #expect(contents.contains { $0.lastPathComponent.contains("(1)") } == false)
    }

    @Test("A distinct track still saves normally")
    func distinctContentStillSaves() async throws {
        let track = try makeTrack(audioURL: "https://cdn.example.com/a.mp3")
        let documents = try temporaryDirectory()

        let downloader = PlaylistTrackDownloader(
            documentsURL: documents,
            playlistSource: URL(string: "https://example.com/list.json")
        ) { _ in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try Data("unique-bytes".utf8).write(to: temp)
            return (temp, URLResponse())
        }

        let outcome = try await downloader.download(
            track,
            existing: DuplicateAudioIndex([])
        )

        guard case .saved(let file) = outcome else {
            Issue.record("A distinct track should save")
            return
        }
        #expect(file.filename == "Rapid Induction.mp3")
    }
}
