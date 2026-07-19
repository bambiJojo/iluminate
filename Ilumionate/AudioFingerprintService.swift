//
//  AudioFingerprintService.swift
//  Ilumionate
//

import CryptoKit
import Foundation

/// Computes content fingerprints away from the main actor during import.
actor AudioFingerprintService {
    static let shared = AudioFingerprintService()

    func fingerprint(for url: URL) -> String? {
        Self.computeFingerprint(for: url)
    }

    nonisolated static func computeFingerprint(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        var readAnyData = false

        while let chunk = try? handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            readAnyData = true
            hasher.update(data: chunk)
        }

        guard readAnyData else { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
