//
//  Folder.swift
//  Ilumionate
//
//  User-created folders for organizing audio sessions in the Library.
//

import Foundation

// MARK: - Folder Model

struct Folder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var icon: String         // SF Symbol name
    var colorName: String    // Key into TranceColors palette (e.g. "roseGold", "lavender")
    var audioFileIds: [UUID]
    var createdDate: Date = Date()

    init(name: String, icon: String = "folder.fill", colorName: String = "roseGold", audioFileIds: [UUID] = []) {
        self.name = name
        self.icon = icon
        self.colorName = colorName
        self.audioFileIds = audioFileIds
    }
}

// MARK: - FolderStore

@Observable
final class FolderStore {

    static let shared = FolderStore()

    var folders: [Folder] = []

    private let storageKey = "userFolders"

    init() { load() }

    // MARK: CRUD

    func create(name: String, icon: String = "folder.fill", colorName: String = "roseGold") {
        let folder = Folder(name: name, icon: icon, colorName: colorName)
        folders.append(folder)
        persist()
    }

    func update(_ folder: Folder) {
        if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[idx] = folder
            persist()
        }
    }

    func delete(_ folder: Folder) {
        folders.removeAll { $0.id == folder.id }
        persist()
    }

    // MARK: File membership

    func addFile(_ fileId: UUID, to folderId: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        guard !folders[idx].audioFileIds.contains(fileId) else { return }
        folders[idx].audioFileIds.append(fileId)
        persist()
    }

    func removeFile(_ fileId: UUID, from folderId: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[idx].audioFileIds.removeAll { $0 == fileId }
        persist()
    }

    func folders(containing fileId: UUID) -> [Folder] {
        folders.filter { $0.audioFileIds.contains(fileId) }
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Folder].self, from: data) else { return }
        folders = decoded
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
