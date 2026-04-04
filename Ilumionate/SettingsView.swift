//
//  SettingsView.swift
//  LumeSync
//
//  Legacy wrapper that forwards to the canonical ProfileSettingsView.
//

import SwiftUI

extension Bundle {
    var appVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "1" }
}

struct SettingsView: View {
    var body: some View {
        ProfileSettingsView()
    }
}

#Preview {
    SettingsView()
}
