//  ReaderPresetStore.swift
//  Ilumionate
//
//  Per-script reader presets. Imported documents and web articles keep their
//  own speed-training/display choices without affecting bundled scripts.

import Foundation

struct ReaderPreset: Codable, Equatable, Sendable {
    var speedTraining: ReaderSpeedTrainingSettings
    var displayPreferences: ReaderDisplayPreferences

    init(speedTraining: ReaderSpeedTrainingSettings = .standard,
         displayPreferences: ReaderDisplayPreferences = .standard) {
        self.speedTraining = speedTraining
        self.displayPreferences = displayPreferences
    }

    static let standard = ReaderPreset()
}

@MainActor
@Observable
final class ReaderPresetStore {
    static let shared = ReaderPresetStore()

    private let defaults: UserDefaults
    private let storageKey: String
    private var presets: [String: ReaderPreset] = [:]

    init(defaults: UserDefaults = .standard,
         storageKey: String = "textTranceReaderPresets.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    func preset(forScriptId scriptId: String) -> ReaderPreset {
        presets[scriptId] ?? .standard
    }

    func save(_ preset: ReaderPreset, forScriptId scriptId: String) {
        presets[scriptId] = preset
        persist()
    }

    func clear(scriptId: String) {
        presets[scriptId] = nil
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: ReaderPreset].self, from: data) else {
            presets = [:]
            return
        }
        presets = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
