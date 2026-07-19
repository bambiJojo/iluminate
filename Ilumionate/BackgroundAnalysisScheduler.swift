//
//  BackgroundAnalysisScheduler.swift
//  Ilumionate
//
//  Connects the durable analysis queue to iOS BackgroundTasks. Continued
//  processing keeps user-started analysis running when the app is no longer
//  frontmost; processing tasks provide deferred recovery after suspension.
//

import BackgroundTasks
import Foundation
import os
import UIKit

@MainActor
final class BackgroundAnalysisScheduler {
    static let shared = BackgroundAnalysisScheduler()

    static let identifierRoot = "\(Bundle.main.bundleIdentifier ?? "com.byronquine.lumenSync").analysis"
    static let processingIdentifier = "\(identifierRoot).processing"
    static let continuedIdentifierPrefix = "\(identifierRoot).continued."
    static let continuedIdentifierPattern = "\(continuedIdentifierPrefix)*"

    private var hasActiveContinuedRequest = false
    private var continuedRequestIdentifier: String?
    private var didAttemptProcessingRegistration = false
    private var isProcessingHandlerRegistered = false

    private init() {}

    func register() {
        guard !didAttemptProcessingRegistration else { return }
        didAttemptProcessingRegistration = true

        isProcessingHandlerRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.processingIdentifier,
            using: .main
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(processingTask)
        }

        if !isProcessingHandlerRegistered {
            Log.analysis.error("Deferred background analysis handler could not be registered")
        }
    }

    /// Schedule both the immediate iOS 26 continuation and a deferred recovery
    /// request. The continued request is only legal while the app is foregrounded.
    func schedule(for audioFiles: [AudioFile]) {
        scheduleDeferredProcessing()

        guard UIApplication.shared.applicationState == .active else { return }
        guard !hasActiveContinuedRequest else { return }

        let identifier = Self.makeContinuedIdentifier()
        guard registerContinuedHandler(for: identifier) else {
            // Never submit an unregistered request. BackgroundTasks raises an
            // Objective-C exception for this programmer error, so it cannot be
            // recovered from with Swift's do/catch.
            Log.analysis.error("Continued background analysis handler could not be registered")
            return
        }

        let count = max(audioFiles.count, 1)
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Analyzing audio",
            subtitle: count == 1 ? "Preparing your light session" : "Processing \(count) audio files"
        )
        request.strategy = .queue

        do {
            try BGTaskScheduler.shared.submit(request)
            hasActiveContinuedRequest = true
            continuedRequestIdentifier = identifier
            Log.analysis.info("Scheduled continued background analysis")
        } catch {
            // Deferred processing remains scheduled when immediate continuation
            // is unavailable because of current system load or user settings.
            Log.analysis.info("Continued background analysis unavailable: \(error.localizedDescription)")
        }
    }

    func scheduleDeferredProcessing() {
        guard isProcessingHandlerRegistered else {
            Log.analysis.error("Deferred background analysis skipped because its handler is unavailable")
            return
        }

        let request = BGProcessingTaskRequest(identifier: Self.processingIdentifier)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.analysis.info("Scheduled deferred background analysis")
        } catch {
            Log.analysis.error("Could not schedule deferred background analysis: \(error.localizedDescription)")
        }
    }

    func cancelDeferredProcessing() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.processingIdentifier)
    }

    func analysisFinished() {
        cancelDeferredProcessing()
        if let continuedRequestIdentifier {
            BGTaskScheduler.shared.cancel(
                taskRequestWithIdentifier: continuedRequestIdentifier
            )
        }
        continuedRequestIdentifier = nil
        hasActiveContinuedRequest = false
    }

    func resumeWhenForegrounded() {
        Task { @MainActor in
            let pending = await AnalysisProgressStore.shared.allPending()
            guard !pending.isEmpty else { return }
            schedule(for: pending.map(\.audioFile))
            _ = await AnalysisStateManager.shared.resumeInterruptedAnalyses(priority: .utility)
        }
    }

    private func handle(_ task: BGProcessingTask) {
        runAnalysis(for: task, progressTask: nil)
    }

    private func handle(_ task: BGContinuedProcessingTask) {
        hasActiveContinuedRequest = true
        continuedRequestIdentifier = task.identifier
        runAnalysis(for: task, progressTask: task)
    }

    static func makeContinuedIdentifier(id: UUID = UUID()) -> String {
        continuedIdentifierPrefix + id.uuidString
    }

    /// Continued-processing handlers must be registered for each concrete
    /// identifier. The wildcard belongs only in Info.plist; registering the
    /// wildcard itself is rejected by BackgroundTasks on iOS 26.
    @discardableResult
    func registerContinuedHandler(for identifier: String) -> Bool {
        guard identifier.hasPrefix(Self.continuedIdentifierPrefix),
              !identifier.contains("*") else {
            return false
        }

        return BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: .main
        ) { [weak self] task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(continuedTask)
        }
    }

    private func runAnalysis(
        for systemTask: BGTask,
        progressTask: BGContinuedProcessingTask?
    ) {
        let operation = Task { @MainActor [weak self] in
            let initialPendingCount = max(
                await AnalysisProgressStore.shared.allPending().count,
                1
            )
            let reporter = Task { @MainActor in
                guard let progressTask else { return }
                progressTask.progress.totalUnitCount = 1_000
                var greatestReportedFraction = 0.0

                while !Task.isCancelled {
                    let remainingCount = await AnalysisProgressStore.shared.allPending().count
                    let currentFraction = AnalysisStateManager.shared.currentAnalysis?.progress ?? 0
                    let completedCount = max(initialPendingCount - remainingCount, 0)
                    let overallFraction = min(
                        (Double(completedCount) + currentFraction) / Double(initialPendingCount),
                        0.999
                    )
                    greatestReportedFraction = max(greatestReportedFraction, overallFraction)
                    progressTask.progress.completedUnitCount = Int64(greatestReportedFraction * 1_000)

                    if let filename = AnalysisStateManager.shared.currentAnalysis?.audioFile.filename {
                        progressTask.updateTitle(
                            "Analyzing audio",
                            subtitle: filename
                        )
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }

            let succeeded = await AnalysisStateManager.shared
                .resumeInterruptedAnalyses(priority: .utility)
            reporter.cancel()

            if let progressTask, succeeded {
                progressTask.progress.completedUnitCount = progressTask.progress.totalUnitCount
            }
            systemTask.setTaskCompleted(success: succeeded)

            if succeeded {
                self?.analysisFinished()
            } else {
                self?.continuedRequestIdentifier = nil
                self?.hasActiveContinuedRequest = false
                self?.scheduleDeferredProcessing()
            }
        }

        systemTask.expirationHandler = { [weak self] in
            operation.cancel()
            Task { @MainActor in
                AnalysisStateManager.shared.expireBackgroundProcessing()
                self?.continuedRequestIdentifier = nil
                self?.hasActiveContinuedRequest = false
                self?.scheduleDeferredProcessing()
            }
        }
    }
}
