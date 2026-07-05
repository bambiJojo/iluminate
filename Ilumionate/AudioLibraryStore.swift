//
//  AudioLibraryStore.swift
//  Ilumionate
//

import AVFoundation
import Foundation
import os

enum AudioLibraryStore {
    private static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac"]

    static func loadRepairingStoredFiles(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        documentsURL: URL = .documentsDirectory
    ) -> [AudioFile] {
        var files = load(defaults: defaults)
        let addedFiles = discoverUnregisteredDocumentFiles(
            existingFiles: files,
            fileManager: fileManager,
            documentsURL: documentsURL
        )

        guard !addedFiles.isEmpty else {
            return files
        }

        files.insert(contentsOf: addedFiles, at: 0)
        save(files, defaults: defaults)
        Log.audio.info("📦 Registered \(addedFiles.count) audio file(s) discovered in Documents")
        return files
    }

    static func load(defaults: UserDefaults = .standard) -> [AudioFile] {
        guard
            let data = defaults.data(forKey: AnalysisStateManager.audioFilesUserDefaultsKey),
            let files = try? JSONDecoder().decode([AudioFile].self, from: data)
        else {
            return []
        }

        return files
    }

    static func save(_ files: [AudioFile], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(files) else {
            Log.audio.info("❌ Failed to encode \(files.count) audio file(s)")
            return
        }

        defaults.set(data, forKey: AnalysisStateManager.audioFilesUserDefaultsKey)
    }

    private static func discoverUnregisteredDocumentFiles(
        existingFiles: [AudioFile],
        fileManager: FileManager,
        documentsURL: URL
    ) -> [AudioFile] {
        let existingFilenames = Set(existingFiles.map { $0.url.lastPathComponent })

        let urls = (try? fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { url in
                supportedExtensions.contains(url.pathExtension.lowercased())
            }
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .filter { url in
                !existingFilenames.contains(url.lastPathComponent)
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                return AudioFile(
                    filename: url.lastPathComponent,
                    duration: audioDuration(url),
                    fileSize: Int64(values?.fileSize ?? 0),
                    createdDate: values?.creationDate ?? Date()
                )
            }
    }

    private static func audioDuration(_ url: URL) -> Double {
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            return 0
        }

        return player.duration.isFinite ? player.duration : 0
    }
}
