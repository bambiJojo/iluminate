//  VisualFieldStore.swift
//  Ilumionate
//
//  The last-used Visual Field settings, so reopening Create restores what you
//  had rather than resetting to the defaults — which is what MindMachineModel
//  did as plain @State, and is why nobody's Create settings ever stuck.

import Foundation
import os

@MainActor
@Observable
final class VisualFieldStore {

    static let defaultsKey = "visualFieldSettings"

    static let shared = VisualFieldStore()

    private let defaults: UserDefaults

    var settings: VisualFieldSettings {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    private static func load(from defaults: UserDefaults) -> VisualFieldSettings {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return .standard
        }
        guard let decoded = try? JSONDecoder().decode(VisualFieldSettings.self, from: data) else {
            // Unreadable settings are not worth surfacing to the user, but they
            // are worth knowing about — VisualFieldSettings.init(from:) falls
            // back field by field, so reaching here at all means the payload was
            // not even a JSON object.
            Log.ui.info("Visual field settings unreadable; starting from defaults")
            return .standard
        }
        return decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
