//
//  AppSupportLink.swift
//  Ilumionate
//
//  Published pages used by both Settings and App Store Connect.
//

import Foundation

enum AppSupportLink: String, CaseIterable {
    case support = "https://github.com/bambiJojo/iluminate/issues"
    case privacyPolicy = "https://github.com/bambiJojo/iluminate/blob/main/PRIVACY_POLICY.md"

    var url: URL? { URL(string: rawValue) }
}
