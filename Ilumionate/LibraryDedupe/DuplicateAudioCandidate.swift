//
//  DuplicateAudioCandidate.swift
//  Ilumionate
//
//  What is known about a file that has not entered the library yet.
//
//  Deliberately partial. Before a download only the publisher's identity, the
//  advertised size and the published duration exist; the fingerprint arrives
//  only once the bytes do. One type covers both moments so the caller does not
//  need two lookup methods that could disagree.
//

import Foundation

nonisolated struct DuplicateAudioCandidate: Sendable {
    var remoteSource: RemoteAudioSource?
    var contentFingerprint: String?
    /// Nil when the server did not report a length.
    var fileSize: Int64?
    var duration: TimeInterval
    /// A filename or a track title — `AudioTitleNormalizer` handles both.
    var title: String

    init(
        remoteSource: RemoteAudioSource? = nil,
        contentFingerprint: String? = nil,
        fileSize: Int64? = nil,
        duration: TimeInterval,
        title: String
    ) {
        self.remoteSource = remoteSource
        self.contentFingerprint = contentFingerprint
        self.fileSize = fileSize
        self.duration = duration
        self.title = title
    }
}
