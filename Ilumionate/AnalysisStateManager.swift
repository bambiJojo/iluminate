//
//  AnalysisStateManager.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/24/26.
//

import Foundation
import Observation

/// Manages background analysis state across the app
@Observable
@MainActor
class AnalysisStateManager {

    // MARK: - State

    var currentAnalysis: ActiveAnalysis?
    var analysisQueue: [AudioFile] = []
    var completedAnalyses: [CompletedAnalysis] = []
    var onAnalysisComplete: ((AudioFile, CompletedAnalysis) -> Void)?

    private var isProcessingQueue = false

    private var audioAnalyzer = AudioAnalyzer()
    private var aiAnalyzer = AIContentAnalyzer()

    // MARK: - Analysis Control

    /// Start analyzing an audio file in the background
    func startAnalysis(for audioFile: AudioFile) async {
        // Add to queue if not already there
        if !analysisQueue.contains(where: { $0.id == audioFile.id }) {
            analysisQueue.append(audioFile)
        }

        // Start processing queue if not already running
        if !isProcessingQueue {
            await processQueue()
        }
    }

    /// Add multiple files to the analysis queue
    func startAnalysis(for audioFiles: [AudioFile]) async {
        // Add all files to queue (avoid duplicates)
        for audioFile in audioFiles {
            if !analysisQueue.contains(where: { $0.id == audioFile.id }) {
                analysisQueue.append(audioFile)
            }
        }

        // Start processing queue if not already running
        if !isProcessingQueue {
            await processQueue()
        }
    }

    /// Cancel the current analysis
    func cancelCurrentAnalysis() {
        audioAnalyzer.cancelTranscription()
        currentAnalysis = nil
    }

    /// Cancel all analyses in queue
    func cancelAllAnalyses() {
        audioAnalyzer.cancelTranscription()
        currentAnalysis = nil
        analysisQueue.removeAll()
        isProcessingQueue = false
    }

    /// Remove a specific file from the queue
    func removeFromQueue(_ audioFile: AudioFile) {
        analysisQueue.removeAll { $0.id == audioFile.id }
    }

    /// Get queue position for a file (0-based, -1 if not in queue)
    func queuePosition(for audioFile: AudioFile) -> Int {
        analysisQueue.firstIndex { $0.id == audioFile.id } ?? -1
    }

    /// Check if a file is in the queue
    func isInQueue(_ audioFile: AudioFile) -> Bool {
        analysisQueue.contains { $0.id == audioFile.id }
    }

    /// Get overall progress (0.0 to 1.0)
    var overallProgress: Double {
        guard let analysis = currentAnalysis else { return 0.0 }

        switch analysis.stage {
        case .starting:
            return 0.0
        case .transcribing:
            return 0.0 + (audioAnalyzer.progress * 0.4)
        case .analyzing:
            return 0.4 + (aiAnalyzer.progress * 0.4)
        case .generatingSession:
            return 0.8
        case .complete:
            return 1.0
        case .failed:
            return 0.0
        }
    }

    // MARK: - Private Analysis Logic

    /// Process the analysis queue
    private func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true

        while !analysisQueue.isEmpty {
            let audioFile = analysisQueue.removeFirst()

            // Create new analysis task
            currentAnalysis = ActiveAnalysis(
                audioFile: audioFile,
                stage: .starting,
                progress: 0.0
            )

            // Perform the analysis
            await performAnalysis(audioFile: audioFile)
        }

        isProcessingQueue = false
    }

    private func performAnalysis(audioFile: AudioFile) async {
        guard currentAnalysis != nil else { return }

        do {
            // Stage 1: Transcription
            currentAnalysis?.stage = .transcribing
            let transcriptionResult = try await audioAnalyzer.transcribe(audioFile: audioFile)

            guard currentAnalysis != nil else { return } // Check if cancelled

            // Stage 2: AI Analysis
            currentAnalysis?.stage = .analyzing
            let analysisResult = try await aiAnalyzer.analyzeContent(
                transcription: transcriptionResult,
                audioFile: audioFile
            )

            guard currentAnalysis != nil else { return } // Check if cancelled

            // Stage 3: Generate Light Session
            currentAnalysis?.stage = .generatingSession
            let lightScoreGenerator = AudioLightScoreGenerator()
            let lightSession = lightScoreGenerator.generateLightScore(
                from: audioFile,
                analysis: analysisResult,
                transcription: transcriptionResult
            )

            // Save the light session
            try saveGeneratedSession(lightSession, for: audioFile)

            guard currentAnalysis != nil else { return } // Check if cancelled

            // Complete
            currentAnalysis?.stage = .complete

            // Save completed analysis
            let completedAnalysis = CompletedAnalysis(
                audioFile: audioFile,
                transcription: transcriptionResult,
                analysis: analysisResult,
                completedAt: Date()
            )
            completedAnalyses.append(completedAnalysis)

            // Notify completion handler
            onAnalysisComplete?(audioFile, completedAnalysis)

            // Clear current analysis after a delay
            try? await Task.sleep(for: .seconds(1))
            if currentAnalysis?.stage == .complete {
                currentAnalysis = nil
            }

        } catch {
            currentAnalysis?.stage = .failed
            currentAnalysis?.errorMessage = error.localizedDescription
            print("❌ Analysis failed: \(error)")

            // Clear failed analysis after delay
            try? await Task.sleep(for: .seconds(2))
            currentAnalysis = nil
        }
    }

    /// Get completed analysis for a file
    func getCompletedAnalysis(for audioFile: AudioFile) -> CompletedAnalysis? {
        completedAnalyses.first { $0.audioFile.id == audioFile.id }
    }

    /// Remove completed analysis
    func removeCompletedAnalysis(for audioFile: AudioFile) {
        completedAnalyses.removeAll { $0.audioFile.id == audioFile.id }
    }

    /// Save generated light session to documents directory
    private func saveGeneratedSession(_ session: LightSession, for audioFile: AudioFile) throws {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionsURL = documentsURL.appendingPathComponent("GeneratedSessions", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: sessionsURL.path) {
            try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        }

        // Create filename from audio file
        let baseName = audioFile.filename
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: ".wav", with: "")
        let filename = "\(baseName)_session.json"
        let fileURL = sessionsURL.appendingPathComponent(filename)

        // Encode and save
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: fileURL)

        print("💾 Saved generated session: \(filename)")
        print("📍 Location: \(fileURL.path)")
    }
}

// MARK: - Active Analysis Model

struct ActiveAnalysis: Equatable {
    let audioFile: AudioFile
    var stage: AnalysisStage
    var progress: Double
    var errorMessage: String?

    static func == (lhs: ActiveAnalysis, rhs: ActiveAnalysis) -> Bool {
        lhs.audioFile.id == rhs.audioFile.id &&
        lhs.stage == rhs.stage &&
        lhs.progress == rhs.progress &&
        lhs.errorMessage == rhs.errorMessage
    }
}

// MARK: - Completed Analysis Model

struct CompletedAnalysis: Identifiable {
    let id = UUID()
    let audioFile: AudioFile
    let transcription: AudioTranscriptionResult
    let analysis: AnalysisResult
    let completedAt: Date
}
