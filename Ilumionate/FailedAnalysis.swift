//
//  FailedAnalysis.swift
//  Ilumionate
//
//  Model for a failed analysis attempt, surfaced in AnalyzerView.
//

import Foundation

struct FailedAnalysis: Identifiable, Sendable {
    let id = UUID()
    let audioFile: AudioFile
    let errorMessage: String
    let failedAt: Date
}
