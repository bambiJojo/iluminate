//
//  PlaylistTrackDownloader.swift
//  Ilumionate
//

import AVFoundation
import Foundation

/// Fetches a missing playlist track from the publisher's own CDN.
///
/// Only the URL the playlist service itself published is ever requested, and
/// only over https from a host the app recognises — a tampered or hostile
/// response cannot redirect the download at an arbitrary server. The saved file
/// is named after the track so a later import matches it without help.
nonisolated struct PlaylistTrackDownloader: Sendable {
    typealias Loader = @Sendable (URL) async throws -> (URL, URLResponse)
    typealias Prober = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let allowedHostSuffix = "bambicloud.com"
    /// Above this the user is asked before the bytes are spent, rather than
    /// being refused. There is no ceiling once they have said yes.
    static let confirmationThresholdBytes: Int64 = 100_000_000
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac"]

    private let load: Loader
    private let probe: Prober
    private let documentsURL: URL

    init(session: URLSession = .shared, documentsURL: URL = .documentsDirectory) {
        load = { try await session.download(from: $0) }
        probe = { try await session.data(for: $0) }
        self.documentsURL = documentsURL
    }

    init(
        documentsURL: URL,
        probe: @escaping Prober = { _ in (Data(), URLResponse()) },
        load: @escaping Loader
    ) {
        self.documentsURL = documentsURL
        self.probe = probe
        self.load = load
    }

    /// Asks the CDN how big the file is without fetching it, so the user can be
    /// told what a large download will cost before it starts. Returns nil when
    /// the server does not say.
    func expectedSize(of track: BambiCloudPlaylist.Track) async throws -> Int64? {
        let source = try validatedSource(for: track)

        var request = URLRequest(url: source, timeoutInterval: 15)
        request.httpMethod = "HEAD"

        guard let (_, response) = try? await probe(request) else {
            return nil
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            return nil
        }
        return response.expectedContentLength > 0 ? response.expectedContentLength : nil
    }

    func download(
        _ track: BambiCloudPlaylist.Track,
        allowingLargeFile: Bool = false
    ) async throws -> AudioFile {
        let source = try validatedSource(for: track)

        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await load(source)
        } catch let error as PlaylistTrackDownloadError {
            throw error
        } catch {
            throw PlaylistTrackDownloadError.networkUnavailable
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw PlaylistTrackDownloadError.networkUnavailable
        }
        if !allowingLargeFile,
           response.expectedContentLength > Self.confirmationThresholdBytes {
            throw PlaylistTrackDownloadError.confirmationRequired(
                byteCount: response.expectedContentLength
            )
        }

        let destination = uniqueDestination(for: track, source: source)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            throw PlaylistTrackDownloadError.couldNotSave
        }

        let byteCount = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if !allowingLargeFile, Int64(byteCount) > Self.confirmationThresholdBytes {
            try? FileManager.default.removeItem(at: destination)
            throw PlaylistTrackDownloadError.confirmationRequired(
                byteCount: Int64(byteCount)
            )
        }

        return AudioFile(
            filename: destination.lastPathComponent,
            duration: await measuredDuration(of: destination, fallback: track.duration),
            fileSize: Int64(byteCount),
            contentFingerprint: AudioFingerprintService.computeFingerprint(for: destination),
            remoteSource: RemoteAudioSource(
                service: RemoteAudioSource.bambiCloudService,
                trackID: track.id.uuidString,
                url: source
            )
        )
    }

    private func validatedSource(
        for track: BambiCloudPlaylist.Track
    ) throws -> URL {
        guard let audioURL = track.audioURL else {
            throw PlaylistTrackDownloadError.noSourceAvailable
        }
        guard audioURL.scheme?.lowercased() == "https",
              let host = audioURL.host()?.lowercased(),
              host == Self.allowedHostSuffix || host.hasSuffix(".\(Self.allowedHostSuffix)")
        else {
            throw PlaylistTrackDownloadError.unsupportedSource
        }
        return audioURL
    }

    /// Prefers the track's own title so the importer's title matching can find
    /// this file again on a later import.
    private func uniqueDestination(
        for track: BambiCloudPlaylist.Track,
        source: URL
    ) -> URL {
        let sourceExtension = source.pathExtension.lowercased()
        let fileExtension = Self.audioExtensions.contains(sourceExtension)
            ? sourceExtension
            : "mp3"

        var safeName = track.name
            .replacing(/[\/\\:]+/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if safeName.isEmpty {
            safeName = source.deletingPathExtension().lastPathComponent
        }

        var candidate = documentsURL.appending(path: "\(safeName).\(fileExtension)")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = documentsURL.appending(path: "\(safeName) (\(counter)).\(fileExtension)")
            counter += 1
        }
        return candidate
    }

    /// The playlist already publishes each track's duration, so the file is only
    /// probed when it does not. That keeps the common path off AVFoundation,
    /// which under the Catalyst sandbox trips a mach-lookup precondition on
    /// `com.apple.audioanalyticsd`.
    private func measuredDuration(
        of url: URL,
        fallback: TimeInterval
    ) async -> TimeInterval {
        guard fallback <= 0 else { return fallback }

        guard let duration = try? await AVURLAsset(url: url).load(.duration) else {
            return fallback
        }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : fallback
    }
}
