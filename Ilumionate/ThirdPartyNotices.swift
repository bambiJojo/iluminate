//
//  ThirdPartyNotices.swift
//  Ilumionate
//
//  Loads the license and NOTICE material shipped with the app. Keeping the
//  inventory here also gives the release tests a stable way to detect when a
//  resolved dependency was omitted from the acknowledgements.
//

import Foundation
import SwiftUI

nonisolated enum ThirdPartyNotices {
    static let requiredComponents = [
        "Swift Argument Parser",
        "SwiftASN1",
        "Swift Collections",
        "Swift Crypto",
        "Swift Jinja",
        "Swift Transformers",
        "TelemetryDeck SwiftSDK",
        "WhisperKit",
        "yyjson",
        "argmaxinc/whisperkit-coreml"
    ]

    static func text(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(
            forResource: "ThirdPartyNotices",
            withExtension: "txt"
        ) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func missingComponents(in text: String) -> [String] {
        requiredComponents.filter { text.contains($0) == false }
    }
}

struct ThirdPartyAcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    private let notices = ThirdPartyNotices.text()
        ?? "Third-party acknowledgements could not be loaded."

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    Text(notices)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(TranceSpacing.screen)
                }
            }
            .navigationTitle("Acknowledgements")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.roseGold)
                }
            }
        }
    }
}
