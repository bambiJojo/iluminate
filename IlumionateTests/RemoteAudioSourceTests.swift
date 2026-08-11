//
//  RemoteAudioSourceTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct RemoteAudioSourceTests {
    @Test("Round-trips through the library encoding")
    func roundTripsThroughCoding() throws {
        let url = try #require(URL(string: "https://cdn.bambicloud.com/a.mp3"))
        var file = AudioFile(filename: "a.mp3", duration: 60, fileSize: 1_000)
        file.remoteSource = RemoteAudioSource(
            service: "bambicloud",
            trackID: "c311778b-d79b-4f3a-8729-3474cda134b4",
            url: url
        )

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(AudioFile.self, from: data)

        #expect(decoded.remoteSource == file.remoteSource)
    }

    // Every library already stored on disk predates this field. Decoding must
    // not start failing for them.
    @Test("A stored file without provenance still decodes")
    func absentProvenanceDecodes() throws {
        let json = Data(
            """
            {"id":"\(UUID().uuidString)","filename":"a.mp3","duration":60,
             "fileSize":1000,"createdDate":0}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(AudioFile.self, from: json)

        #expect(decoded.remoteSource == nil)
        #expect(decoded.filename == "a.mp3")
    }
}

// ERR-004: `==` listed fields explicitly and had never been revisited when
// contentFingerprint or remoteSource were added, so two values referring to
// different audio compared equal.
struct AudioFileIdentityEqualityTests {
    private func makeFile() -> AudioFile {
        AudioFile(filename: "Track.mp3", duration: 600, fileSize: 5_000_000)
    }

    @Test("Files differing only in content fingerprint are not equal")
    func fingerprintParticipatesInEquality() {
        var a = makeFile()
        var b = a
        a.contentFingerprint = "aaa"
        b.contentFingerprint = "bbb"

        #expect(a != b)
    }

    @Test("Files differing only in provenance are not equal")
    func provenanceParticipatesInEquality() throws {
        var a = makeFile()
        var b = a
        a.remoteSource = RemoteAudioSource(
            service: RemoteAudioSource.bambiCloudService,
            trackID: "one",
            url: try #require(URL(string: "https://cdn.bambicloud.com/one.mp3"))
        )
        b.remoteSource = RemoteAudioSource(
            service: RemoteAudioSource.bambiCloudService,
            trackID: "two",
            url: try #require(URL(string: "https://cdn.bambicloud.com/two.mp3"))
        )

        #expect(a != b)
    }

    @Test("An unchanged copy is still equal")
    func identicalCopiesRemainEqual() {
        let a = makeFile()
        #expect(a == a)
    }

    // The reason `==` is not narrowed to `id`: SwiftUI diffs on it.
    @Test("An in-place edit still reports a change")
    func inPlaceEditIsVisible() {
        let a = makeFile()
        var b = a
        b.userTitle = "Renamed"

        #expect(a != b)
    }
}
