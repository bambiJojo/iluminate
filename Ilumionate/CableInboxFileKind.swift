//
//  CableInboxFileKind.swift
//  Ilumionate
//

import Foundation

/// What a settled inbox file is, and therefore which subsystem may admit it.
///
/// Classification is by extension alone. Content validation is deliberately
/// left to the admitting step, which already does it and can explain a failure
/// in its own terms: audio checks its magic bytes, and a document that is
/// really binary fails extraction and is filed as invalid.
nonisolated enum CableInboxFileKind: Sendable, Equatable {
    case audio
    case readerDocument
    case unrecognized

    init(url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        if AudioDownloadValidation.audioExtensions.contains(fileExtension) {
            self = .audio
        } else if ReadingDocumentImporter.supportedFileExtensions.contains(fileExtension) {
            self = .readerDocument
        } else {
            self = .unrecognized
        }
    }
}
