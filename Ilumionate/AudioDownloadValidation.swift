//
//  AudioDownloadValidation.swift
//  Ilumionate
//
//  Decides whether bytes fetched from a URL are actually audio.
//
//  This exists because the URL importer used to trust the request rather than the
//  response: a link that returned a web page was saved with an `.mp3` extension,
//  reported as "✅ Successfully downloaded audio", and admitted to the library,
//  where it looked like a normal track but could never play or analyse. Telemetry
//  showed the consequence — 116 files imported, 16 ever analysed — with no import
//  error ever recorded, because nothing in the path considered it a failure.
//
//  THE BYTES ARE THE AUTHORITY. A `Content-Type` header is a claim, and a URL
//  ending in `.mp3` is barely even that. Both are checked, but neither can
//  override a payload that plainly is not audio.
//

import Foundation

enum AudioDownloadValidation {

    enum Rejection: Error, Equatable {
        /// The server told us it was not audio.
        case unsupportedContentType(String)
        /// The payload does not begin with a supported audio container.
        case notAudioData

        var userFacingMessage: String {
            switch self {
            case .unsupportedContentType:
                return "That link returned a web page, not an audio file. "
                    + "Check that it points directly at an MP3, M4A, or WAV."
            case .notAudioData:
                return "That file doesn't look like audio. "
                    + "Check that the link points directly at an MP3, M4A, or WAV."
            }
        }
    }

    /// File extensions accepted from a URL path.
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac"]

    // MARK: - Gate

    /// `nil` when the payload may be admitted to the library.
    ///
    /// The header is consulted first because it gives the clearest explanation to
    /// the user, but a header claiming audio never rescues a non-audio payload.
    static func rejectionReason(contentType: String?, data: Data) -> Rejection? {
        if let contentType, !contentType.isEmpty, isDefinitelyNotAudio(contentType) {
            return .unsupportedContentType(contentType)
        }
        guard looksLikeAudio(data) else { return .notAudioData }
        return nil
    }

    // MARK: - Content-Type

    /// The extension implied by a `Content-Type`, or `nil` when it is not audio.
    ///
    /// Deliberately returns `nil` rather than falling back to `mp3` — guessing is
    /// exactly how HTML ended up in the library.
    static func audioExtension(forContentType contentType: String) -> String? {
        let normalized = contentType
            .lowercased()
            .components(separatedBy: ";")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        guard normalized.hasPrefix("audio/") else { return nil }

        if normalized.contains("mpeg") || normalized.contains("mp3") { return "mp3" }
        if normalized.contains("mp4") || normalized.contains("m4a") { return "m4a" }
        if normalized.contains("wav") { return "wav" }
        if normalized.contains("flac") { return "flac" }
        if normalized.contains("aac") { return "aac" }
        return nil
    }

    /// Types that rule audio out. `application/octet-stream` and friends are
    /// left to the byte check, since plenty of servers use them for real audio.
    private static func isDefinitelyNotAudio(_ contentType: String) -> Bool {
        let normalized = contentType
            .lowercased()
            .components(separatedBy: ";")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""

        if normalized.hasPrefix("audio/") { return false }
        return normalized.hasPrefix("text/")
            || normalized.hasPrefix("image/")
            || normalized.hasPrefix("video/")
            || normalized == "application/json"
            || normalized == "application/xml"
            || normalized == "application/xhtml+xml"
    }

    // MARK: - Magic bytes

    /// The extension implied by the payload's container signature.
    static func inferredExtension(from data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return nil }

        // "ID3" tag, or an MPEG frame sync (11 bits set).
        if bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 { return "mp3" }
        if bytes[0] == 0xFF, bytes[1] & 0xE0 == 0xE0 {
            // ADTS AAC shares the sync word; its layer bits are zero.
            return bytes[1] & 0x06 == 0 ? "aac" : "mp3"
        }
        // ISO base media: size, then "ftyp".
        if bytes.count >= 8,
           bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            return "m4a"
        }
        // "RIFF" .... "WAVE"
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x41, bytes[10] == 0x56, bytes[11] == 0x45 {
            return "wav"
        }
        // "fLaC"
        if bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 {
            return "flac"
        }
        return nil
    }

    static func looksLikeAudio(_ data: Data) -> Bool {
        inferredExtension(from: data) != nil
    }
}
