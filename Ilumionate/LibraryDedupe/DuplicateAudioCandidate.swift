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
    /// Nil when the duration is not known yet — the Files-picker path has not
    /// loaded the asset at the point it asks. Distinct from zero, which would
    /// silently claim a zero-length recording and let a real library entry of
    /// about that length match on it.
    var duration: TimeInterval?
    /// A filename or a track title — `AudioTitleNormalizer` handles both.
    var title: String

    init(
        remoteSource: RemoteAudioSource? = nil,
        contentFingerprint: String? = nil,
        fileSize: Int64? = nil,
        duration: TimeInterval? = nil,
        title: String
    ) {
        self.remoteSource = remoteSource
        self.contentFingerprint = contentFingerprint
        self.fileSize = fileSize
        self.duration = duration
        self.title = title
    }
}
