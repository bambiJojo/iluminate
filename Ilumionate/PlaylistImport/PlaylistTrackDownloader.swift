//
//  PlaylistTrackDownloader.swift
//  Ilumionate
//

import AVFoundation
import Foundation

/// What a download resolved to.
///
/// A download that turns out to duplicate audio the library already holds is a
/// success, not a failure — the playlist row it was fetched for gets the copy
/// that already carries the user's analysis, rating and play count.
nonisolated enum PlaylistTrackDownloadOutcome: Sendable, Equatable {
    case saved(AudioFile)
    case alreadyInLibrary(existing: AudioFile.ID)
}

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

    init(session: URLSession = .shared, documentsURL: URL = AppStoragePaths.managedAudio) {
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

    /// Fetches a track, unless the library already holds it.
    ///
    /// The duplicate check sits between the transfer and the move into
    /// `Documents`. It used to sit nowhere at all: `uniqueDestination` ran
    /// first, so a file the user already had was written a second time as
    /// "Name (1).mp3" before anything had a chance to object.
    func download(
        _ track: BambiCloudPlaylist.Track,
        allowingLargeFile: Bool = false,
        existing: DuplicateAudioIndex = DuplicateAudioIndex([])
    ) async throws -> PlaylistTrackDownloadOutcome {
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
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PlaylistTrackDownloadError.networkUnavailable
        }
        if !allowingLargeFile,
           response.expectedContentLength > Self.confirmationThresholdBytes {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PlaylistTrackDownloadError.confirmationRequired(
                byteCount: response.expectedContentLength
            )
        }

        // Read from the temp file, before the move. The ceiling used to be
        // re-checked against a file already sitting in Documents, which then
        // had to be deleted again.
        let byteCount = Int64(
            (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        )
        if !allowingLargeFile, byteCount > Self.confirmationThresholdBytes {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PlaylistTrackDownloadError.confirmationRequired(byteCount: byteCount)
        }

        let fingerprint = AudioFingerprintService.computeFingerprint(for: temporaryURL)
        let remoteSource = RemoteAudioSource(
            service: RemoteAudioSource.bambiCloudService,
            trackID: track.id.uuidString,
            url: source
        )

        let verdict = existing.verdict(
            for: DuplicateAudioCandidate(
                remoteSource: remoteSource,
                contentFingerprint: fingerprint,
                fileSize: byteCount,
                duration: track.duration,
                title: track.name
            )
        )
        // Only a conclusive verdict discards bytes already paid for. A merely
        // likely one is the user's call, and reaches them as a review row.
        if case .identical(let existingID) = verdict {
            try? FileManager.default.removeItem(at: temporaryURL)
            return .alreadyInLibrary(existing: existingID)
        }

        let destination = uniqueDestination(for: track, source: source)
        do {
            try FileManager.default.createDirectory(
                at: documentsURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PlaylistTrackDownloadError.couldNotSave
        }

        return .saved(
            AudioFile(
                filename: destination.lastPathComponent,
                duration: await measuredDuration(of: destination, fallback: track.duration),
                fileSize: byteCount,
                contentFingerprint: fingerprint,
                storageLocation: .managed,
                remoteSource: remoteSource
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
