//
//  AnalysisAvailabilityPresentation.swift
//  Ilumionate
//
//  Names analysis capabilities without promising Foundation Models on systems
//  where only the built-in compatibility analyzer is available.
//

import Foundation

enum AnalysisAvailabilityPresentation {

    static func cardLabel(supportsFoundationModels: Bool) -> String {
        supportsFoundationModels ? "Light Sync AI" : "Light Sync Analysis"
    }

    static func sectionTitle(supportsFoundationModels: Bool) -> String {
        supportsFoundationModels ? "AI Analysis" : "Built-In Analysis"
    }
}
