#!/usr/bin/env swift
//
//  sync-simulator-drop.swift
//
//  Copies files from SimulatorDrop/ into the booted simulator's Ilumionate
//  Documents folder and registers them in the app's audioFiles UserDefaults key.
//

import AVFoundation
import Foundation

struct Options {
    var bundleID = "com.byronquine.Ilumionate"
    var simulator = "booted"
    var dropFolder = "SimulatorDrop"
    var deleteAfterImport = false
    var pruneDuplicates = false
}

let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac"]
let fileManager = FileManager.default

do {
    let options = try parseOptions(CommandLine.arguments.dropFirst())
    let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    let dropURL = URL(fileURLWithPath: options.dropFolder, relativeTo: root).standardizedFileURL

    guard directoryExists(dropURL) else {
        throw SyncError.message("Drop folder not found: \(dropURL.path)")
    }

    let sourceFiles = try audioFiles(in: dropURL)
    guard !sourceFiles.isEmpty || options.pruneDuplicates else {
        print("No supported audio files found in \(dropURL.path).")
        exit(0)
    }

    let containerURL = try simulatorContainerURL(bundleID: options.bundleID, simulator: options.simulator)
    print("Target simulator: \(options.simulator)")
    print("App container: \(containerURL.path)")
    terminateApp(bundleID: options.bundleID, simulator: options.simulator)

    let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
    try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)

    let preferencesURL = containerURL
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Preferences", isDirectory: true)
        .appendingPathComponent("\(options.bundleID).plist")

    var preferences = try loadPreferences(at: preferencesURL)
    var library = try loadAudioLibrary(from: preferences)
    if options.pruneDuplicates {
        let removedCount = try pruneNumericDuplicates(from: &library, documentsURL: documentsURL)
        print("Removed \(removedCount) duplicate file\(removedCount == 1 ? "" : "s").")
    }

    var existingFilenames = Set(library.compactMap { $0["filename"] as? String })

    var importedCount = 0
    for sourceURL in sourceFiles {
        let sourceFilename = sourceURL.lastPathComponent
        if existingFilenames.contains(sourceFilename) {
            print("Already registered: \(sourceFilename)")
            if options.deleteAfterImport {
                try? fileManager.removeItem(at: sourceURL)
            }
            continue
        }

        let destinationURL = uniqueDestinationURL(
            for: sourceFilename,
            in: documentsURL
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let filename = destinationURL.lastPathComponent
        if existingFilenames.contains(filename) || library.contains(where: { ($0["filename"] as? String) == filename }) {
            print("Copied but already registered: \(filename)")
        } else {
            library.insert(audioFileRecord(for: destinationURL), at: 0)
            existingFilenames.insert(filename)
            importedCount += 1
            print("Imported: \(filename)")
        }

        if options.deleteAfterImport {
            try? fileManager.removeItem(at: sourceURL)
        }
    }

    preferences["audioFiles"] = try JSONSerialization.data(withJSONObject: library, options: [])
    try savePreferences(preferences, at: preferencesURL)

    print("Done. Registered \(importedCount) new file\(importedCount == 1 ? "" : "s").")
    launchApp(bundleID: options.bundleID, simulator: options.simulator)
} catch {
    fputs("sync-simulator-drop: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// MARK: - Options

func parseOptions(_ arguments: ArraySlice<String>) throws -> Options {
    var options = Options()
    var iterator = arguments.makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--bundle-id":
            guard let value = iterator.next(), !value.isEmpty else {
                throw SyncError.message("Missing value after --bundle-id")
            }
            options.bundleID = value
        case "--simulator", "--simulator-id":
            guard let value = iterator.next(), !value.isEmpty else {
                throw SyncError.message("Missing value after \(argument)")
            }
            options.simulator = value
        case "--drop-folder":
            guard let value = iterator.next(), !value.isEmpty else {
                throw SyncError.message("Missing value after --drop-folder")
            }
            options.dropFolder = value
        case "--delete-after-import":
            options.deleteAfterImport = true
        case "-h", "--help":
            print("""
            Usage: ./Tools/sync-simulator-drop.swift [options]

            Options:
              --bundle-id ID          App bundle id. Default: com.byronquine.Ilumionate
              --simulator ID|booted    Simulator target. Default: booted
              --drop-folder PATH      Folder to import from. Default: SimulatorDrop
              --delete-after-import   Remove files from the drop folder after copying
              --prune-duplicates      Remove numeric duplicate imports like Song-1.mp3
            """)
            exit(0)
        case "--prune-duplicates":
            options.pruneDuplicates = true
        default:
            throw SyncError.message("Unknown argument: \(argument)")
        }
    }

    return options
}

// MARK: - Simulator

func simulatorContainerURL(bundleID: String, simulator: String) throws -> URL {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl", "get_app_container", simulator, bundleID, "data"]
    process.standardOutput = output
    process.standardError = error

    try process.run()
    process.waitUntilExit()

    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    let path = String(data: outputData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard process.terminationStatus == 0, !path.isEmpty else {
        let message = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw SyncError.message(message ?? "Could not find simulator app container for \(bundleID). Run the app once first.")
    }

    return URL(fileURLWithPath: path, isDirectory: true)
}

func terminateApp(bundleID: String, simulator: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl", "terminate", simulator, bundleID]
    process.standardOutput = nil
    process.standardError = nil
    try? process.run()
    process.waitUntilExit()
}

func launchApp(bundleID: String, simulator: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["simctl", "launch", simulator, bundleID]
    process.standardOutput = nil
    process.standardError = nil
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            print("Launched \(bundleID) in the booted simulator.")
        } else {
            print("Files are synced. Launch \(bundleID) in the simulator to see them.")
        }
    } catch {
        print("Files are synced. Launch \(bundleID) in the simulator to see them.")
    }
}

// MARK: - Files

func directoryExists(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
}

func audioFiles(in folder: URL) throws -> [URL] {
    try fileManager.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )
    .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

func uniqueDestinationURL(for filename: String, in folder: URL) -> URL {
    let original = folder.appendingPathComponent(filename)
    guard fileManager.fileExists(atPath: original.path) else { return original }

    let base = original.deletingPathExtension().lastPathComponent
    let ext = original.pathExtension

    for index in 1...999 {
        let candidateName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
        let candidate = folder.appendingPathComponent(candidateName)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
    }

    return folder.appendingPathComponent("\(UUID().uuidString)-\(filename)")
}

// MARK: - Preferences

func loadPreferences(at url: URL) throws -> [String: Any] {
    guard fileManager.fileExists(atPath: url.path) else { return [:] }
    let data = try Data(contentsOf: url)
    guard !data.isEmpty else { return [:] }

    let object = try PropertyListSerialization.propertyList(
        from: data,
        options: [.mutableContainersAndLeaves],
        format: nil
    )
    return object as? [String: Any] ?? [:]
}

func savePreferences(_ preferences: [String: Any], at url: URL) throws {
    try fileManager.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let data = try PropertyListSerialization.data(
        fromPropertyList: preferences,
        format: .binary,
        options: 0
    )
    try data.write(to: url, options: .atomic)
}

func loadAudioLibrary(from preferences: [String: Any]) throws -> [[String: Any]] {
    guard let data = preferences["audioFiles"] as? Data, !data.isEmpty else {
        return []
    }
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [[String: Any]] ?? []
}

func audioFileRecord(for fileURL: URL) -> [String: Any] {
    [
        "id": UUID().uuidString,
        "filename": fileURL.lastPathComponent,
        "duration": audioDuration(fileURL),
        "fileSize": fileSize(fileURL),
        "createdDate": Date().timeIntervalSinceReferenceDate
    ]
}

func pruneNumericDuplicates(from library: inout [[String: Any]], documentsURL: URL) throws -> Int {
    let filenames = Set(library.compactMap { $0["filename"] as? String })
    var removedFilenames = Set<String>()

    library.removeAll { record in
        guard
            let filename = record["filename"] as? String,
            let original = originalFilename(forNumericDuplicate: filename),
            filenames.contains(original)
        else {
            return false
        }

        removedFilenames.insert(filename)
        return true
    }

    for filename in removedFilenames {
        let fileURL = documentsURL.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    return removedFilenames.count
}

func originalFilename(forNumericDuplicate filename: String) -> String? {
    let url = URL(fileURLWithPath: filename)
    let ext = url.pathExtension
    let base = url.deletingPathExtension().lastPathComponent

    guard let range = base.range(of: #"-\d+$"#, options: .regularExpression) else {
        return nil
    }

    let originalBase = String(base[..<range.lowerBound])
    guard !originalBase.isEmpty else { return nil }
    return ext.isEmpty ? originalBase : "\(originalBase).\(ext)"
}

func audioDuration(_ url: URL) -> Double {
    let asset = AVURLAsset(url: url)
    let seconds = CMTimeGetSeconds(asset.duration)
    return seconds.isFinite ? seconds : 0
}

func fileSize(_ url: URL) -> Int64 {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    return Int64(values?.fileSize ?? 0)
}

enum SyncError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}
