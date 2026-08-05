//  ReaderPresetStore.swift
//  Ilumionate
//
//  Per-script reader presets. Imported documents and web articles keep their
//  own speed-training/display choices without affecting bundled scripts.

import Foundation

struct ReaderPreset: Codable, Equatable, Sendable {
    var speedTraining: ReaderSpeedTrainingSettings
    var displayPreferences: ReaderDisplayPreferences
    /// User override for the reader mode. `nil` means "use the value derived
    /// from the script's source kind" — see `ReaderMode.derived(from:)`. Being
    /// Optional is what keeps presets written before this field existed
    /// decodable: synthesized Codable decodes optionals with `decodeIfPresent`.
    var mode: ReaderMode?

    init(speedTraining: ReaderSpeedTrainingSettings = .standard,
         displayPreferences: ReaderDisplayPreferences = .standard,
         mode: ReaderMode? = nil) {
        self.speedTraining = speedTraining
        self.displayPreferences = displayPreferences
        self.mode = mode
    }

    /// The mode to use for `script`: the user's override when they have set one,
    /// otherwise the value derived from how the content arrived.
    func resolvedMode(for script: TranceScript) -> ReaderMode {
        mode ?? ReaderMode.derived(from: script.source)
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
        guard let data = defaults.data(forKey: storageKey) else {
            presets = [:]
            return
        }
        // Per-entry, so one unreadable script's preset costs that script only.
        // Decoding the dictionary whole meant a single bad entry wiped every
        // script's saved reader preferences at once.
        let (decoded, dropped) = ResilientDecoding.dictionary(ReaderPreset.self, from: data)
        presets = decoded
        if dropped > 0 { persist() }   // write back without the unreadable entries
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
