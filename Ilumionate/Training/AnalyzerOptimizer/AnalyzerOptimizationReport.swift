//
//  AnalyzerOptimizationReport.swift
//  Ilumionate
//
//  Report models for analyzer optimizer runs.
//

import Foundation

struct AnalyzerTrainingMatchScorecard: Codable, Sendable {
    struct SplitSummary: Codable, Sendable {
        let name: String
        let exampleCount: Int
        let metrics: AnalyzerOptimizationAggregateMetrics
        let matchPercentage: Double
    }

    let generatedAt: Date
    let optimizerVersion: Int
    let evaluationMode: AnalyzerEvaluationMode
    let dataset: AnalyzerOptimizationDataset.Summary
    let configGeneration: Int
    let configFitness: Double
    let evaluatedExampleCount: Int
    let overallMetrics: AnalyzerOptimizationAggregateMetrics
    let matchPercentage: Double
    let splitSummaries: [SplitSummary]
    let worstMatches: [AnalyzerOptimizationReport.FileDiagnostic]
}

struct AnalyzerTrainingMatchHistory: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let generatedAt: Date
        let evaluationMode: AnalyzerEvaluationMode
        let datasetHash: String
        let evaluatedExampleCount: Int
        let configGeneration: Int
        let configFitness: Double
        let matchPercentage: Double
        let overallMetrics: AnalyzerOptimizationAggregateMetrics
    }

    let updatedAt: Date
    let entries: [Entry]
}

struct AnalyzerOptimizationReport: Codable, Sendable {
    struct GenerationSnapshot: Codable, Sendable {
        let generation: Int
        let bestTrainingScore: Double
        let bestValidationScore: Double
        let averageTrainingScore: Double
        let averageValidationScore: Double
    }

    struct FileDiagnostic: Codable, Sendable {
        let exampleID: UUID
        let filename: String
        let overallScore: Double
        let timelineAccuracy: Double
        let macroPhaseF1: Double
        let boundaryScore: Double
        let meanBoundaryErrorSeconds: Double
        let transitionRecall: Double
        let orderValidity: Double
    }

    let generatedAt: Date
    let optimizerVersion: Int
    let evaluationMode: AnalyzerEvaluationMode
    let dataset: AnalyzerOptimizationDataset.Summary
    let outputDirectory: String
    let trainCount: Int
    let validationCount: Int
    let testCount: Int
    let baselineTrainingMetrics: AnalyzerOptimizationAggregateMetrics
    let baselineValidationMetrics: AnalyzerOptimizationAggregateMetrics
    let bestTrainingMetrics: AnalyzerOptimizationAggregateMetrics
    let bestValidationMetrics: AnalyzerOptimizationAggregateMetrics
    let testMetrics: AnalyzerOptimizationAggregateMetrics
    let baselineOverallMetrics: AnalyzerOptimizationAggregateMetrics
    let selectedOverallMetrics: AnalyzerOptimizationAggregateMetrics
    let overallImprovement: Double
    let selectedConfigGeneration: Int
    let selectedConfigFitness: Double
    let generationHistory: [GenerationSnapshot]
    let issues: [AnalyzerOptimizationDatasetIssue]
    let diagnostics: [FileDiagnostic]
}

enum AnalyzerOptimizerError: LocalizedError, Sendable {
    case datasetIndexMissing(URL)
    case documentsBackedAudioRequired(URL)
    case transcriberRequired(UUID)
    case emptyDataset
    case outputWriteFailed(URL, underlying: String)
    case evaluationFailed(String)

    var errorDescription: String? {
        switch self {
        case .datasetIndexMissing(let url):
            return "Analyzer dataset index is missing at \(url.path())."
        case .documentsBackedAudioRequired(let url):
            return "Audio transcription requires a Documents-backed file path, but received \(url.path())."
        case .transcriberRequired(let exampleID):
            return "Transcript cache miss for example \(exampleID.uuidString), but no transcriber was provided."
        case .emptyDataset:
            return "No valid analyzer-training examples were available to optimize against."
        case .outputWriteFailed(let url, let underlying):
            return "Could not write optimizer output at \(url.path()): \(underlying)"
        case .evaluationFailed(let message):
            return message
        }
    }
}
