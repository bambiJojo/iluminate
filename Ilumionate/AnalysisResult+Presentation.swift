//
//  AnalysisResult+Presentation.swift
//  Ilumionate
//
//  User-facing provenance for results that may come from either Apple's
//  Foundation Models or the built-in compatibility analyzer.
//

import Foundation

enum AnalysisResultPresentation {

    static func sourceLabel(for result: AnalysisResult) -> String {
        result.usedKeywordFallback ? "Keyword Analysis" : "AI Analyzed"
    }

    static func insightsLabel(for result: AnalysisResult) -> String {
        result.usedKeywordFallback ? "Built-In Insights" : "AI Insights"
    }
}
