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
