//
//  DownloadedTrackAnalysisTests.swift
//  IlumionateTests
//
//  A downloaded track has no light session yet, so it should reach the analyser
//  the same way a browser-imported file does.
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct DownloadedTrackAnalysisTests {
    private func playlistJSON(trackName: String) -> (Data, UUID) {
        let playlistID = UUID()
        let json = """
        {"playlists":[{"uuid":"\(playlistID.uuidString)","name":"P","files":[
        {"uuid":"\(UUID().uuidString)","name":"\(trackName)","duration":600000,
         "audioURL":"https://cdn.bambicloud.com/x.mp3","trackNum":0}]}]}
        """
        return (Data(json.utf8), playlistID)
    }

    private func makeModel(
        documents: URL,
        autoAnalyse: Bool,
        onQueue: @escaping @MainActor (AudioFile) -> Void
    ) throws -> (BambiCloudPlaylistImportViewModel, BambiCloudPlaylistImportPlan.Row) {
        let (data, playlistID) = playlistJSON(trackName: "Fuck Doll")
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        let downloader = PlaylistTrackDownloader(documentsURL: documents) { url in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try Data(repeating: 7, count: 128).write(to: temp)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (temp, response)
        }

        let model = BambiCloudPlaylistImportViewModel(
            availableAudioFiles: [],
            downloader: downloader,
            isAutoAnalyseEnabled: { autoAnalyse },
            analysisQueue: { audioFile in onQueue(audioFile) }
        )

        let plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: []
        )
        model.adoptPlanForTesting(plan)
        let row = try #require(plan.rows.first)
        return (model, row)
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func downloadedTrackIsQueuedForAnalysis() async throws {
        var queued: [AudioFile] = []
        let (model, row) = try makeModel(
            documents: try temporaryDirectory(),
            autoAnalyse: true
        ) {
            queued.append($0)
        }

        await model.downloadRow(row)

        #expect(queued.count == 1)
        #expect(queued.first?.filename == "Fuck Doll.mp3")
    }

    @Test func autoAnalyseOffLeavesTheAnalyserAlone() async throws {
        var queued: [AudioFile] = []
        let (model, row) = try makeModel(
            documents: try temporaryDirectory(),
            autoAnalyse: false
        ) {
            queued.append($0)
        }

        await model.downloadRow(row)

        // The file still lands in the library; only analysis is skipped.
        #expect(queued.isEmpty)
        #expect(model.availableAudioFiles.count == 1)
    }
}
