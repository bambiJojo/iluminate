//
//  AppSupportLink.swift
//  Ilumionate
//
//  Published pages used by both Settings and App Store Connect.
//

import Foundation

enum AppSupportLink: String, CaseIterable {
    case support = "https://quineent.wixsite.com/lumesync/support"
    case privacyPolicy = "https://quineent.wixsite.com/lumesync/privacy-policy"

    var url: URL? { URL(string: rawValue) }
}
