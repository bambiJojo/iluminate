//  ShareViewController.swift
//  IlumionateShareExtension

import Foundation
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureStatusView()

        Task { @MainActor in
            await importSharedItems()
        }
    }

    private func configureStatusView() {
        view.backgroundColor = UIColor(red: 0.03, green: 0.05, blue: 0.11, alpha: 1)
        statusLabel.text = "Importing to LumeSync..."
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func importSharedItems() async {
        do {
            let items = try await sharedImportItems()
            guard !items.isEmpty else {
                finish(message: "Nothing readable found")
                return
            }

            try ShareImportQueueWriter.append(items)
            statusLabel.text = "Opening LumeSync..."
            _ = await extensionContext?.open(ShareImportQueueWriter.deepLinkURL)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            finish(message: error.localizedDescription)
        }
    }

    private func finish(message: String) {
        statusLabel.text = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func sharedImportItems() async throws -> [ShareImportItem] {
        let extensionItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        var result: [ShareImportItem] = []

        for item in extensionItems {
            let title = item.attributedTitle?.string ?? item.attributedContentText?.string
            for provider in item.attachments ?? [] {
                if let fileItem = try await fileImportItem(from: provider, title: title) {
                    result.append(fileItem)
                    continue
                }
                if let urlItem = try await urlImportItem(from: provider, title: title) {
                    result.append(urlItem)
                    continue
                }
                if let textItem = try await textImportItem(from: provider, title: title) {
                    result.append(textItem)
                    continue
                }
            }
        }

        return result
    }

    private func urlImportItem(from provider: NSItemProvider, title: String?) async throws -> ShareImportItem? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        let item = try await provider.loadItem(typeIdentifier: UTType.url.identifier)
        let url = normalizedURL(from: item)
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return ShareImportItem(
            id: UUID().uuidString,
            kind: .webURL,
            title: title,
            sourceURLString: url.absoluteString,
            fileName: nil,
            originalFilename: nil,
            text: nil,
            createdAt: Date()
        )
    }

    private func textImportItem(from provider: NSItemProvider, title: String?) async throws -> ShareImportItem? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        let item = try await provider.loadItem(typeIdentifier: UTType.plainText.identifier)
        let text: String?
        if case .string(let string) = item {
            text = string
        } else if case .data(let data) = item {
            text = String(data: data, encoding: .utf8)
        } else {
            text = nil
        }
        guard let text, text.split(whereSeparator: \.isWhitespace).count >= 8 else { return nil }
        return ShareImportItem(
            id: UUID().uuidString,
            kind: .plainText,
            title: title,
            sourceURLString: nil,
            fileName: nil,
            originalFilename: nil,
            text: text,
            createdAt: Date()
        )
    }

    private func fileImportItem(from provider: NSItemProvider, title: String?) async throws -> ShareImportItem? {
        let supportedTypes = ShareImportQueueWriter.supportedFileTypes
        guard let type = supportedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            return nil
        }

        let item = try await provider.loadItem(typeIdentifier: type.identifier)
        guard let sourceURL = normalizedURL(from: item) else { return nil }
        let ext = sourceURL.pathExtension.isEmpty ? type.preferredFilenameExtension ?? "dat" : sourceURL.pathExtension
        guard ShareImportQueueWriter.isSupportedFileExtension(ext) else { return nil }

        let fileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = ShareImportQueueWriter.filesDirectoryURL.appending(path: fileName)
        try await ShareFileImportWorker.copy(from: sourceURL, to: destinationURL)

        return ShareImportItem(
            id: UUID().uuidString,
            kind: .file,
            title: title,
            sourceURLString: nil,
            fileName: fileName,
            originalFilename: sourceURL.lastPathComponent,
            text: nil,
            createdAt: Date()
        )
    }

    private func normalizedURL(from item: LoadedProviderItem) -> URL? {
        if case .url(let url) = item { return url }
        if case .string(let string) = item { return URL(string: string) ?? URL(fileURLWithPath: string) }
        if case .data(let data) = item,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string) ?? URL(fileURLWithPath: string)
        }
        return nil
    }
}

private extension NSItemProvider {
    func loadItem(typeIdentifier: String) async throws -> LoadedProviderItem {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = item as? URL {
                    continuation.resume(returning: .url(url))
                } else if let url = item as? NSURL {
                    continuation.resume(returning: .url(url as URL))
                } else if let string = item as? String {
                    continuation.resume(returning: .string(string))
                } else if let data = item as? Data {
                    continuation.resume(returning: .data(data))
                } else {
                    continuation.resume(throwing: ShareImportError.unreadableItem)
                }
            }
        }
    }
}

private enum LoadedProviderItem: Sendable {
    case url(URL)
    case string(String)
    case data(Data)
}

private nonisolated enum ShareFileImportWorker {
    @concurrent
    static func copy(from sourceURL: URL, to destinationURL: URL) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { sourceURL.stopAccessingSecurityScopedResource() }
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
}

private enum ShareImportKind: String, Codable {
    case webURL
    case file
    case plainText
}

private struct ShareImportItem: Codable {
    let id: String
    let kind: ShareImportKind
    let title: String?
    let sourceURLString: String?
    let fileName: String?
    let originalFilename: String?
    let text: String?
    let createdAt: Date
}

private enum ShareImportError: LocalizedError {
    case unreadableItem

    var errorDescription: String? {
        switch self {
        case .unreadableItem:
            return "The shared item could not be read."
        }
    }
}

private enum ShareImportQueueWriter {
    static let appGroupIdentifier = "group.com.byronquine.lumenSync"
    static let deepLinkURL = URL(string: "ilumionate://shared-import")!

    private static let directoryName = "SharedReaderImports"
    private static let filesDirectoryName = "Files"
    private static let queueFilename = "imports.json"

    static var supportedFileTypes: [UTType] {
        var types: [UTType] = [.pdf]
        if let epub = UTType(filenameExtension: "epub") {
            types.append(epub)
        }
        return types
    }

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return url
        }
        return FileManager.default.temporaryDirectory
            .appending(path: directoryName, directoryHint: .isDirectory)
    }

    static var filesDirectoryURL: URL {
        containerURL.appending(path: filesDirectoryName, directoryHint: .isDirectory)
    }

    private static var queueURL: URL {
        containerURL.appending(path: queueFilename)
    }

    static func append(_ newItems: [ShareImportItem]) throws {
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)

        var items: [ShareImportItem] = []
        if let data = try? Data(contentsOf: queueURL),
           let decoded = try? JSONDecoder().decode([ShareImportItem].self, from: data) {
            items = decoded
        }
        items.append(contentsOf: newItems)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: queueURL, options: .atomic)
    }

    static func isSupportedFileExtension(_ fileExtension: String) -> Bool {
        switch fileExtension.lowercased() {
        case "pdf", "epub": return true
        default: return false
        }
    }
}
