//
//  Bundle+Version.swift
//  LumeSync
//
//  App version strings, read from the bundle's Info dictionary.
//
//  This file also used to declare `SettingsView`, a wrapper whose whole body was
//  `ProfileSettingsView()`. Nothing constructed it — settings is reached from the
//  home toolbar on iOS and the sidebar `SettingsLink` on macOS, both of which
//  present `ProfileSettingsView` directly — so the wrapper is gone and only the
//  version helpers remain.
//

import Foundation

extension Bundle {
    var appVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "1" }
}
