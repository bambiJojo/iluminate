//
//  ContentAddressedCacheTests.swift
//  IlumionateTests
//
//  Tests for Step 4.4: Content-addressed analysis cache.
//  Verifies:
//  1. contentAddressedKey produces consistent SHA-256 hex output.
//  2. Same content + same model → same key (deterministic).
//  3. Different content → different key.
//  4. Different model version → different key (automatic invalidation).
//  5. cacheKey falls back to UUID when the file can't be read.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Helpers

/// Writes `data` to a temp file and returns the URL.
private func tempFile(data: Data, ext: String = "m4a") throws -> URL {
    let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(ext)")
    try data.write(to: url)
    return url
}

/// Returns an AudioFile pointing at a temp file containing `data`.
private func makeAudioFile(data: Data) throws -> (AudioFile, URL) {
    let url = try tempFile(data: data)
    let file = AudioFile(
        id: UUID(),
        filename: url.lastPathComponent,
        duration: 300,
        fileSize: Int64(data.count),
        createdDate: Date()
    )
    // Synthesize url access — AudioFile stores filename, not URL directly.
    // We test contentAddressedKey(audioFileURL:) directly.
    return (file, url)
}

// MARK: - contentAddressedKey Tests

struct ContentAddressedKeyTests {

    @Test func keyIsHexColonVersion() throws {
        let data = Data(repeating: 0xAB, count: 100)
        let url  = try tempFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let key = AnalysisStateManager.contentAddressedKey(audioFileURL: url)
        #expect(key != nil, "Key must be non-nil for a readable file")
        // Format: 64-char hex + ":" + model version
        let parts = key!.components(separatedBy: ":")
        #expect(parts.count == 2, "Key must have exactly one ':' separator")
        #expect(parts[0].count == 64, "SHA-256 hex must be 64 chars, got \(parts[0].count)")
        #expect(parts[1] == AnalysisStateManager.currentModelVersion)
    }

    @Test func sameContentProducesSameKey() throws {
        let data = Data(repeating: 0x42, count: 1024)
        let url1 = try tempFile(data: data)
        let url2 = try tempFile(data: data)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let key1 = AnalysisStateManager.contentAddressedKey(audioFileURL: url1)
        let key2 = AnalysisStateManager.contentAddressedKey(audioFileURL: url2)
        #expect(key1 == key2,
            "Same audio content must produce identical keys: \(key1 ?? "nil") vs \(key2 ?? "nil")")
    }

    @Test func differentContentProducesDifferentKeys() throws {
        let data1 = Data(repeating: 0x01, count: 1024)
        let data2 = Data(repeating: 0x02, count: 1024)
        let url1  = try tempFile(data: data1)
        let url2  = try tempFile(data: data2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let key1 = AnalysisStateManager.contentAddressedKey(audioFileURL: url1)
        let key2 = AnalysisStateManager.contentAddressedKey(audioFileURL: url2)
        #expect(key1 != key2,
            "Different content must produce different keys")
    }

    @Test func differentModelVersionProducesDifferentKey() throws {
        let data = Data(repeating: 0x99, count: 512)
        let url  = try tempFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let keyV1 = AnalysisStateManager.contentAddressedKey(audioFileURL: url, modelVersion: "base-v1")
        let keyV2 = AnalysisStateManager.contentAddressedKey(audioFileURL: url, modelVersion: "base-v2")
        #expect(keyV1 != keyV2,
            "Different model versions must produce different keys for cache invalidation")
    }

    @Test func nonExistentFileReturnsNil() {
        let url = URL.temporaryDirectory.appending(path: "doesNotExist_\(UUID().uuidString).m4a")
        let key = AnalysisStateManager.contentAddressedKey(audioFileURL: url)
        #expect(key == nil, "Non-existent file must return nil key")
    }

    @Test func keyUsesCompleteFileContents() throws {
        // Matching headers are common in encoded audio. Trailing differences must
        // still produce different content identities.
        let chunk    = Data(repeating: 0xCC, count: 64 * 1024)
        let trailer1 = Data(repeating: 0x00, count: 1024)
        let trailer2 = Data(repeating: 0xFF, count: 1024)
        let url1 = try tempFile(data: chunk + trailer1)
        let url2 = try tempFile(data: chunk + trailer2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        let key1 = AnalysisStateManager.contentAddressedKey(audioFileURL: url1)
        let key2 = AnalysisStateManager.contentAddressedKey(audioFileURL: url2)
        #expect(key1 != key2,
            "Files differing beyond their shared header must not collide")
    }

    @Test func storedFingerprintAvoidsReadingTheFileAgain() {
        let fingerprint = String(repeating: "a", count: 64)
        let file = AudioFile(
            filename: "already-deleted.m4a",
            duration: 300,
            fileSize: 1024,
            contentFingerprint: fingerprint
        )

        #expect(
            AnalysisStateManager.cacheKey(for: file)
                == "\(fingerprint):\(AnalysisStateManager.currentModelVersion)"
        )
    }
}

// MARK: - cacheKey Fallback

struct CacheKeyFallbackTests {

    @Test func fallsBackToUUIDForMissingFile() {
        let fakeURL = URL.temporaryDirectory.appending(path: "missing_\(UUID().uuidString).m4a")
        let file = AudioFile(
            id: UUID(),
            filename: fakeURL.lastPathComponent,
            duration: 300,
            fileSize: 0,
            createdDate: Date()
        )
        let key = AnalysisStateManager.cacheKey(for: file)
        #expect(
            key == "\(file.id.uuidString):\(AnalysisStateManager.currentModelVersion)",
            "Legacy UUID-backed entries must still include the analysis version so analyzer improvements invalidate them."
        )
    }
}
